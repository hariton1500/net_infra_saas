create table if not exists public.company_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  invited_email text not null,
  role text not null default 'member' check (role in ('admin', 'member')),
  invited_by_user_id uuid not null references auth.users (id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked')),
  token text not null unique default encode(gen_random_bytes(18), 'hex'),
  accepted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create index if not exists company_invites_company_id_idx
  on public.company_invites (company_id);

create index if not exists company_invites_email_idx
  on public.company_invites (lower(invited_email));

alter table public.company_invites enable row level security;

create or replace function public.current_user_company_id()
returns uuid
language sql
security definer
set search_path = public
stable
as $$
  select company_id
  from public.company_members
  where user_id = auth.uid()
  limit 1;
$$;

drop policy if exists "Members can read company memberships in own company" on public.company_members;
create policy "Members can read company memberships in own company"
on public.company_members
for select
to authenticated
using (company_id = public.current_user_company_id());

drop policy if exists "Company members can read company invites" on public.company_invites;
create policy "Company members can read company invites"
on public.company_invites
for select
to authenticated
using (
  company_id in (
    select company_id
    from public.company_members
    where user_id = auth.uid()
  )
);

create or replace function public.current_user_company_role(target_company_id uuid)
returns text
language sql
security definer
set search_path = public
stable
as $$
  select role
  from public.company_members
  where user_id = auth.uid()
    and company_id = target_company_id
  limit 1;
$$;

create or replace function public.create_company_invite(
  invited_email_input text,
  role_input text default 'member'
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

  if normalized_email = '' then
    raise exception 'Invite email is required';
  end if;

  if normalized_role not in ('admin', 'member') then
    raise exception 'Unsupported role';
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
    invited_by_user_id
  )
  values (
    actor_membership.company_id,
    normalized_email,
    normalized_role,
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

  update public.company_invites
  set status = 'accepted',
      accepted_at = timezone('utc', now())
  where id = pending_invite.id;

  return pending_invite.company_id;
end;
$$;

grant select on public.company_invites to authenticated;
grant execute on function public.create_company_invite(text, text) to authenticated;
grant execute on function public.accept_company_invite() to authenticated;
