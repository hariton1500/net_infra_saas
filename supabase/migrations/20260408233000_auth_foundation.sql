create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  full_name text not null default '',
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

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

create or replace function public.set_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists profiles_set_updated_at on public.profiles;
create trigger profiles_set_updated_at
before update on public.profiles
for each row
execute procedure public.set_updated_at();

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

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    coalesce(new.email, ''),
    coalesce(new.raw_user_meta_data ->> 'full_name', '')
  )
  on conflict (id) do update
  set
    email = excluded.email,
    full_name = case
      when excluded.full_name <> '' then excluded.full_name
      else public.profiles.full_name
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

alter table public.profiles enable row level security;
alter table public.companies enable row level security;
alter table public.company_members enable row level security;

drop policy if exists "Users can read own profile" on public.profiles;
create policy "Users can read own profile"
on public.profiles
for select
to authenticated
using ((select auth.uid()) = id);

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

drop policy if exists "Members can read company memberships" on public.company_members;
create policy "Members can read company memberships"
on public.company_members
for select
to authenticated
using (
  exists (
    select 1
    from public.company_members as own_membership
    where own_membership.company_id = company_members.company_id
      and own_membership.user_id = auth.uid()
  )
);

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert on public.companies to authenticated;
grant select on public.company_members to authenticated;
grant execute on function public.create_company_with_owner(text) to authenticated;
