alter table public.company_module_records
  add column if not exists task_id bigint;

create index if not exists company_module_records_company_module_task_idx
  on public.company_module_records (company_id, module_key, task_id);
