update auth.users
set raw_user_meta_data = jsonb_set(
  coalesce(raw_user_meta_data, '{}'::jsonb),
  '{position}',
  to_jsonb(case
    when lower(trim(raw_user_meta_data ->> 'position')) = 'chief engineer' then 'Chief Engineer'
    when lower(trim(raw_user_meta_data ->> 'position')) = 'engineer' then 'Engineer'
    when lower(trim(raw_user_meta_data ->> 'position')) = 'installer' then 'Installer'
    when trim(raw_user_meta_data ->> 'position') = 'Главный инженер' then 'Chief Engineer'
    when trim(raw_user_meta_data ->> 'position') = 'Инженер' then 'Engineer'
    when trim(raw_user_meta_data ->> 'position') = 'Монтажник' then 'Installer'
    else 'Engineer'
  end),
  true
)
where raw_user_meta_data ? 'position'
  and raw_user_meta_data ->> 'position' not in (
    'Chief Engineer',
    'Engineer',
    'Installer'
  );

do $$
begin
  if not exists (
    select 1
    from pg_type
    join pg_namespace on pg_namespace.oid = pg_type.typnamespace
    where pg_namespace.nspname = 'public'
      and pg_type.typname = 'employee_position'
  ) then
    create domain public.employee_position as text
    check (value in ('Chief Engineer', 'Engineer', 'Installer'));
  end if;
end $$;

drop trigger if exists profiles_normalize_position on public.profiles;

drop trigger if exists company_invites_normalize_position
on public.company_invites;

drop function if exists public.normalize_employee_position_columns();

drop function if exists public.normalize_employee_position_value(text);

create or replace function public.normalize_employee_position_value(
  position_input text
)
returns public.employee_position
language sql
immutable
set search_path = public
as $$
  select (case
    when lower(trim(coalesce(position_input, ''))) = 'chief engineer' then 'Chief Engineer'
    when lower(trim(coalesce(position_input, ''))) = 'engineer' then 'Engineer'
    when lower(trim(coalesce(position_input, ''))) = 'installer' then 'Installer'
    when trim(coalesce(position_input, '')) = 'Главный инженер' then 'Chief Engineer'
    when trim(coalesce(position_input, '')) = 'Инженер' then 'Engineer'
    when trim(coalesce(position_input, '')) = 'Монтажник' then 'Installer'
    when trim(coalesce(position_input, '')) = '' then 'Engineer'
    else 'Engineer'
  end)::public.employee_position;
$$;

create or replace function public.normalize_employee_position_columns()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.position := public.normalize_employee_position_value(new.position::text);
  return new;
end;
$$;

alter table public.profiles
  drop constraint if exists profiles_position_check;

alter table public.company_invites
  drop constraint if exists company_invites_position_check;

alter table public.profiles
  alter column position set default 'Engineer',
  alter column position type public.employee_position
    using public.normalize_employee_position_value(position::text);

alter table public.company_invites
  alter column position set default 'Engineer',
  alter column position type public.employee_position
    using public.normalize_employee_position_value(position::text);

create trigger profiles_normalize_position
before insert or update of position on public.profiles
for each row
execute function public.normalize_employee_position_columns();

create trigger company_invites_normalize_position
before insert or update of position on public.company_invites
for each row
execute function public.normalize_employee_position_columns();

update public.profiles
set position = public.normalize_employee_position_value(position)
where position not in ('Chief Engineer', 'Engineer', 'Installer');

update public.company_invites
set position = public.normalize_employee_position_value(position)
where position not in ('Chief Engineer', 'Engineer', 'Installer');

update auth.users
set raw_user_meta_data = raw_user_meta_data - 'position'
where raw_user_meta_data ? 'position';
