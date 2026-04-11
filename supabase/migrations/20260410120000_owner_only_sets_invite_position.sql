create or replace function public.create_company_invite(
  invited_email_input text,
  role_input text default 'member',
  position_input text default ''
)
returns public.company_invites
language plpgsql
security definer
set search_path = public
as $$
declare
  actor_membership public.company_members%rowtype;
  normalized_email text;
  normalized_role text;
  normalized_position text;
  invite_row public.company_invites%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select *
  into actor_membership
  from public.company_members
  where user_id = auth.uid();

  if actor_membership.id is null then
    raise exception 'Current user does not belong to a company';
  end if;

  if actor_membership.role not in ('owner', 'admin') then
    raise exception 'Only owners and admins can invite employees';
  end if;

  normalized_email := lower(trim(invited_email_input));
  normalized_role := lower(trim(role_input));
  normalized_position := trim(coalesce(position_input, ''));

  if normalized_email = '' then
    raise exception 'Invite email is required';
  end if;

  if normalized_role not in ('admin', 'member') then
    raise exception 'Unsupported role';
  end if;

  if actor_membership.role <> 'owner' then
    normalized_position := 'Монтажник';
  elsif normalized_position = '' then
    normalized_position := 'Монтажник';
  end if;

  if normalized_position not in ('Главный инженер', 'Инженер', 'Монтажник') then
    raise exception 'Unsupported position';
  end if;

  if exists (
    select 1
    from public.company_members
    join public.profiles on profiles.id = company_members.user_id
    where company_members.company_id = actor_membership.company_id
      and lower(profiles.email) = normalized_email
  ) then
    raise exception 'This employee already belongs to your company';
  end if;

  update public.company_invites
  set status = 'revoked'
  where company_id = actor_membership.company_id
    and lower(invited_email) = normalized_email
    and status = 'pending';

  insert into public.company_invites (
    company_id,
    invited_email,
    role,
    position,
    invited_by_user_id
  )
  values (
    actor_membership.company_id,
    normalized_email,
    normalized_role,
    normalized_position,
    auth.uid()
  )
  returning * into invite_row;

  return invite_row;
end;
$$;

grant execute on function public.create_company_invite(text, text, text) to authenticated;
