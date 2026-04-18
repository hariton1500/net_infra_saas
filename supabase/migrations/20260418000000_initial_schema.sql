create extension if not exists pgcrypto;

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  full_name text not null default '',
  position text not null default 'Инженер',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.profiles
  add column if not exists position text not null default 'Инженер';

update public.profiles
set position = 'Инженер'
where trim(coalesce(position, '')) = ''
   or position not in ('Главный инженер', 'Инженер', 'Монтажник');

alter table public.profiles
  alter column position set default 'Инженер';

alter table public.profiles
  drop constraint if exists profiles_position_check;

alter table public.profiles
  add constraint profiles_position_check
  check (position in ('Главный инженер', 'Инженер', 'Монтажник'));

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute procedure public.set_updated_at();

create table if not exists public.companies (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  slug text not null unique,
  owner_user_id uuid not null references auth.users (id) on delete restrict,
  created_at timestamptz not null default timezone('utc', now())
);

create table if not exists public.company_members (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  user_id uuid not null references auth.users (id) on delete cascade,
  role text not null default 'member' check (role in ('owner', 'admin', 'member')),
  created_at timestamptz not null default timezone('utc', now()),
  unique (company_id, user_id),
  unique (user_id)
);

create table if not exists public.company_invites (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  invited_email text not null,
  role text not null default 'member' check (role in ('admin', 'member')),
  position text not null default 'Инженер',
  invited_by_user_id uuid not null references auth.users (id) on delete restrict,
  status text not null default 'pending' check (status in ('pending', 'accepted', 'revoked')),
  token text not null unique default encode(gen_random_bytes(18), 'hex'),
  accepted_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

alter table public.company_invites
  add column if not exists position text not null default 'Инженер';

update public.company_invites
set position = 'Инженер'
where trim(coalesce(position, '')) = ''
   or position not in ('Главный инженер', 'Инженер', 'Монтажник');

alter table public.company_invites
  alter column position set default 'Инженер';

alter table public.company_invites
  drop constraint if exists company_invites_position_check;

alter table public.company_invites
  add constraint company_invites_position_check
  check (position in ('Главный инженер', 'Инженер', 'Монтажник'));

create index if not exists company_invites_company_id_idx
  on public.company_invites (company_id);

create index if not exists company_invites_email_idx
  on public.company_invites (lower(invited_email));

create table if not exists public.company_module_records (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  module_key text not null,
  record_id bigint not null,
  payload jsonb,
  deleted boolean not null default false,
  updated_at timestamptz not null default timezone('utc', now()),
  synced_at timestamptz,
  updated_by_user_id uuid references auth.users (id) on delete set null,
  created_at timestamptz not null default timezone('utc', now()),
  unique (company_id, module_key, record_id)
);

create index if not exists company_module_records_company_module_idx
  on public.company_module_records (company_id, module_key);

create index if not exists company_module_records_updated_at_idx
  on public.company_module_records (updated_at desc);

delete from public.company_module_records
where module_key = 'work_orders';

alter table public.company_module_records
  drop constraint if exists company_module_records_module_key_check;

alter table public.company_module_records
  add constraint company_module_records_module_key_check
  check (
    module_key in (
      'muff_notebook',
      'network_cabinet',
      'cable_lines',
      'projects'
    )
  );

create or replace function public.generate_unique_company_slug(company_name text)
returns text
language plpgsql
as $$
declare
  base_slug text;
  slug_candidate text;
  counter integer := 1;
begin
  base_slug := regexp_replace(lower(trim(company_name)), '[^a-z0-9]+', '-', 'g');
  base_slug := trim(both '-' from base_slug);

  if base_slug = '' then
    base_slug := 'company';
  end if;

  slug_candidate := base_slug;

  while exists (
    select 1
    from public.companies
    where slug = slug_candidate
  ) loop
    counter := counter + 1;
    slug_candidate := base_slug || '-' || counter::text;
  end loop;

  return slug_candidate;
end;
$$;

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

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name, position)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', ''),
    coalesce(nullif(new.raw_user_meta_data ->> 'position', ''), 'Инженер')
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
after insert on auth.users
for each row
execute procedure public.handle_new_user();

create or replace function public.create_company_with_owner(company_name_input text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  requested_company_name text;
  new_company_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  requested_company_name := nullif(trim(company_name_input), '');

  if requested_company_name is null then
    raise exception 'Company name is required';
  end if;

  if exists (
    select 1
    from public.company_members
    where user_id = auth.uid()
  ) then
    raise exception 'User already belongs to a company';
  end if;

  insert into public.companies (name, slug, owner_user_id)
  values (
    requested_company_name,
    public.generate_unique_company_slug(requested_company_name),
    auth.uid()
  )
  returning id into new_company_id;

  insert into public.company_members (company_id, user_id, role)
  values (new_company_id, auth.uid(), 'owner');

  return new_company_id;
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
    when trim(coalesce(position, '')) = '' then coalesce(pending_invite.position, 'Инженер')
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

alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.company_members enable row level security;
alter table public.company_invites enable row level security;
alter table public.company_module_records enable row level security;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

drop policy if exists "Company members can read teammate profiles" on public.profiles;
create policy "Company members can read teammate profiles"
on public.profiles
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members as teammate_membership
    join public.company_members as own_membership
      on own_membership.company_id = teammate_membership.company_id
    where teammate_membership.user_id = profiles.id
      and own_membership.user_id = auth.uid()
  )
);

drop policy if exists "Users can insert own profile" on public.profiles;
create policy "Users can insert own profile"
on public.profiles
for insert
to authenticated
with check ((select auth.uid()) = id);

drop policy if exists "Users can update own profile" on public.profiles;
create policy "Users can update own profile"
on public.profiles
for update
to authenticated
using ((select auth.uid()) = id)
with check ((select auth.uid()) = id);

drop policy if exists "Company members can read companies" on public.companies;
create policy "Company members can read companies"
on public.companies
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members
    where company_members.company_id = companies.id
      and company_members.user_id = auth.uid()
  )
);

drop policy if exists "Owners can create companies" on public.companies;
create policy "Owners can create companies"
on public.companies
for insert
to authenticated
with check (owner_user_id = auth.uid());

drop policy if exists "Users can read own company membership" on public.company_members;
drop policy if exists "Members can read company memberships" on public.company_members;
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

drop policy if exists "Company members can read module records" on public.company_module_records;
create policy "Company members can read module records"
on public.company_module_records
for select
to authenticated
using (company_id = public.current_user_company_id());

drop policy if exists "Company members can insert module records" on public.company_module_records;
create policy "Company members can insert module records"
on public.company_module_records
for insert
to authenticated
with check (company_id = public.current_user_company_id());

drop policy if exists "Company members can update module records" on public.company_module_records;
create policy "Company members can update module records"
on public.company_module_records
for update
to authenticated
using (company_id = public.current_user_company_id())
with check (company_id = public.current_user_company_id());

drop policy if exists "Company members can delete module records" on public.company_module_records;
create policy "Company members can delete module records"
on public.company_module_records
for delete
to authenticated
using (company_id = public.current_user_company_id());

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert on public.companies to authenticated;
grant select on public.company_members to authenticated;
grant select on public.company_invites to authenticated;
grant select, insert, update, delete on public.company_module_records to authenticated;
grant execute on function public.create_company_with_owner(text) to authenticated;
grant execute on function public.create_company_invite(text, text, text) to authenticated;
grant execute on function public.accept_company_invite() to authenticated;
