alter table public.company_module_records
  drop constraint if exists company_module_records_module_key_check;

delete from public.company_module_records
where module_key = 'work_orders';

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
