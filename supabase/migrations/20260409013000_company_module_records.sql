create table if not exists public.company_module_records (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies (id) on delete cascade,
  module_key text not null check (module_key in ('muff_notebook', 'network_cabinet')),
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

alter table public.company_module_records enable row level security;

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

grant select, insert, update, delete on public.company_module_records to authenticated;
