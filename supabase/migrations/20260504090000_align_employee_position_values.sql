alter table public.profiles
  drop constraint if exists profiles_position_check;

alter table public.company_invites
  drop constraint if exists company_invites_position_check;

update public.profiles
set position = case
  when lower(trim(position)) = 'chief engineer' then 'Chief Engineer'
  when lower(trim(position)) = 'engineer' then 'Engineer'
  when lower(trim(position)) = 'installer' then 'Installer'
  when trim(position) = 'Главный инженер' then 'Chief Engineer'
  when trim(position) = 'Инженер' then 'Engineer'
  when trim(position) = 'Монтажник' then 'Installer'
  else 'Engineer'
end
where trim(coalesce(position, '')) = ''
   or lower(trim(position)) in ('chief engineer', 'engineer', 'installer')
   or trim(position) in ('Главный инженер', 'Инженер', 'Монтажник')
   or position not in ('Chief Engineer', 'Engineer', 'Installer');

update public.company_invites
set position = case
  when lower(trim(position)) = 'chief engineer' then 'Chief Engineer'
  when lower(trim(position)) = 'engineer' then 'Engineer'
  when lower(trim(position)) = 'installer' then 'Installer'
  when trim(position) = 'Главный инженер' then 'Chief Engineer'
  when trim(position) = 'Инженер' then 'Engineer'
  when trim(position) = 'Монтажник' then 'Installer'
  else 'Engineer'
end
where trim(coalesce(position, '')) = ''
   or lower(trim(position)) in ('chief engineer', 'engineer', 'installer')
   or trim(position) in ('Главный инженер', 'Инженер', 'Монтажник')
   or position not in ('Chief Engineer', 'Engineer', 'Installer');

alter table public.profiles
  alter column position set default 'Engineer';

alter table public.company_invites
  alter column position set default 'Engineer';

alter table public.profiles
  add constraint profiles_position_check
  check (position in ('Chief Engineer', 'Engineer', 'Installer'));

alter table public.company_invites
  add constraint company_invites_position_check
  check (position in ('Chief Engineer', 'Engineer', 'Installer'));

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  normalized_position text;
begin
  normalized_position := trim(coalesce(new.raw_user_meta_data ->> 'position', ''));

  normalized_position := case
    when lower(normalized_position) = 'chief engineer' then 'Chief Engineer'
    when lower(normalized_position) = 'engineer' then 'Engineer'
    when lower(normalized_position) = 'installer' then 'Installer'
    when normalized_position = 'Главный инженер' then 'Chief Engineer'
    when normalized_position = 'Инженер' then 'Engineer'
    when normalized_position = 'Монтажник' then 'Installer'
    when normalized_position = '' then 'Engineer'
    else 'Engineer'
  end;

  insert into public.profiles (id, email, full_name, position)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    normalized_position
  )
  on conflict (id) do update
  set
    email = excluded.email,
    full_name = case
      when excluded.full_name <> '' then excluded.full_name
      else public.profiles.full_name
    end,
    position = case
      when excluded.position <> '' then excluded.position
      else public.profiles.position
    end;

  return new;
end;
$$;

drop function if exists public.create_company_invite(text, text);
drop function if exists public.create_company_invite(text, text, text);

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

  normalized_position := case
    when lower(normalized_position) = 'chief engineer' then 'Chief Engineer'
    when lower(normalized_position) = 'engineer' then 'Engineer'
    when lower(normalized_position) = 'installer' then 'Installer'
    when normalized_position = 'Главный инженер' then 'Chief Engineer'
    when normalized_position = 'Инженер' then 'Engineer'
    when normalized_position = 'Монтажник' then 'Installer'
    when normalized_position = '' then 'Installer'
    else normalized_position
  end;

  if actor_membership.role <> 'owner' then
    normalized_position := 'Installer';
  end if;

  if normalized_position not in ('Chief Engineer', 'Engineer', 'Installer') then
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

create or replace function public.accept_company_invite()
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  current_profile public.profiles%rowtype;
  pending_invite public.company_invites%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if exists (
    select 1
    from public.company_members
    where user_id = auth.uid()
  ) then
    return null;
  end if;

  select *
  into current_profile
  from public.profiles
  where id = auth.uid();

  if current_profile.id is null then
    raise exception 'Profile not found';
  end if;

  select *
  into pending_invite
  from public.company_invites
  where lower(invited_email) = lower(current_profile.email)
    and status = 'pending'
  order by created_at desc
  limit 1;

  if pending_invite.id is null then
    return null;
  end if;

  insert into public.company_members (company_id, user_id, role)
  values (pending_invite.company_id, auth.uid(), pending_invite.role);

  update public.profiles
  set position = case
    when trim(coalesce(position, '')) = '' then coalesce(pending_invite.position, 'Engineer')
    else position
  end
  where id = auth.uid();

  update public.company_invites
  set status = 'accepted',
      accepted_at = timezone('utc', now())
  where id = pending_invite.id;

  return pending_invite.company_id;
end;
$$;

grant execute on function public.create_company_invite(text, text, text) to authenticated;
grant execute on function public.accept_company_invite() to authenticated;
