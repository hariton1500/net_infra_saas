create or replace function public.cleanup_network_cabinet_cable_splitters(record_payload jsonb)
returns jsonb
language plpgsql
as $$
declare
  next_payload jsonb := coalesce(record_payload, '{}'::jsonb);
  raw_cables jsonb := case
    when jsonb_typeof(next_payload->'cables') = 'array'
      then next_payload->'cables'
    else '[]'::jsonb
  end;
  raw_connections jsonb := case
    when jsonb_typeof(next_payload->'connections') = 'array'
      then next_payload->'connections'
    else '[]'::jsonb
  end;
  cable jsonb;
  connection jsonb;
  splitter_entry record;
  cleaned_cables jsonb := '[]'::jsonb;
  cleaned_connections jsonb := '[]'::jsonb;
  splitter_fibers text[] := '{}';
  splitter_values jsonb;
  cable_id text;
  splitter_value integer;
begin
  for cable in
    select value from jsonb_array_elements(raw_cables) as item(value)
  loop
    cable_id := nullif(cable->>'id', '');
    splitter_values := case
      when jsonb_typeof(cable->'spliters') = 'array'
        then cable->'spliters'
      when jsonb_typeof(cable->'splitters') = 'array'
        then cable->'splitters'
      else null
    end;

    if cable_id is not null and splitter_values is not null then
      for splitter_entry in
        select value, ordinality
        from jsonb_array_elements(splitter_values)
          with ordinality as item(value, ordinality)
      loop
        splitter_value := case
          when splitter_entry.value #>> '{}' ~ '^-?[0-9]+$'
            then (splitter_entry.value #>> '{}')::integer
          else 0
        end;

        if splitter_value > 0 then
          splitter_fibers := array_append(
            splitter_fibers,
            cable_id || ':' || (splitter_entry.ordinality - 1)
          );
        end if;
      end loop;
    end if;

    cleaned_cables := cleaned_cables || jsonb_build_array(
      cable - 'spliters' - 'splitters'
    );
  end loop;

  for connection in
    select value from jsonb_array_elements(raw_connections) as item(value)
  loop
    if array_length(splitter_fibers, 1) is not null and (
      (
        connection ? 'cable1' and
        connection ? 'fiber1' and
        ((connection->>'cable1') || ':' || (connection->>'fiber1')) =
          any(splitter_fibers)
      ) or (
        connection ? 'cable2' and
        connection ? 'fiber2' and
        ((connection->>'cable2') || ':' || (connection->>'fiber2')) =
          any(splitter_fibers)
      )
    ) then
      continue;
    end if;

    cleaned_connections := cleaned_connections || jsonb_build_array(connection);
  end loop;

  next_payload := jsonb_set(next_payload, '{cables}', cleaned_cables, true);
  next_payload := jsonb_set(
    next_payload,
    '{connections}',
    cleaned_connections,
    true
  );
  return next_payload;
end;
$$;

update public.company_module_records
set
  payload = jsonb_set(
    public.cleanup_network_cabinet_cable_splitters(payload),
    '{connections}',
    '[]'::jsonb,
    true
  ),
  updated_at = timezone('utc', now()),
  synced_at = timezone('utc', now())
where module_key = 'network_cabinet'
  and payload is not null
  and (
    payload ? 'connections'
    or exists (
      select 1
      from jsonb_array_elements(
        case
          when jsonb_typeof(payload->'cables') = 'array'
            then payload->'cables'
          else '[]'::jsonb
        end
      ) as cable(value)
      where cable.value ? 'spliters'
         or cable.value ? 'splitters'
    )
  );

drop function public.cleanup_network_cabinet_cable_splitters(jsonb);
