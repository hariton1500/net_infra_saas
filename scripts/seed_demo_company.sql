-- Demo workspace seed for Net Infra SaaS.
-- Intended project: infra_saas / mcwmbwxhevowygtlvmrp.
--
-- Safe to re-run: recreates only the demo company with slug `demo-fiber-city`.
--
-- Demo logins:
--   demo.owner@netinfra.local      / DemoNetInfra2026!
--   demo.engineer@netinfra.local   / DemoNetInfra2026!
--   demo.installer1@netinfra.local / DemoNetInfra2026!
--   demo.installer2@netinfra.local / DemoNetInfra2026!
--   demo.dispatch@netinfra.local   / DemoNetInfra2026!

create extension if not exists pgcrypto;

create or replace function pg_temp.demo_user_id_for(email_input text)
returns uuid
language plpgsql
as $$
declare
  found_id uuid;
begin
  select id
  into found_id
  from auth.users
  where lower(email) = lower(email_input)
  limit 1;

  return coalesce(found_id, gen_random_uuid());
end;
$$;

create or replace function pg_temp.demo_employee_json(
  user_id uuid,
  email_input text,
  full_name_input text,
  position_input text
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'user_id', user_id::text,
    'email', lower(email_input),
    'full_name', full_name_input,
    'position', position_input
  );
$$;

create or replace function pg_temp.demo_cable_json(
  cable_id bigint,
  name_input text,
  fibers_input int,
  side_input int default null
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'id', cable_id,
    'name', name_input,
    'fibers', fibers_input,
    'color_scheme', case when fibers_input <= 12 then 'default' else 'tube' end,
    'fiber_comments', (
      select jsonb_agg(case when idx % 4 = 0 then 'резерв' else '' end order by idx)
      from generate_series(1, fibers_input) as idx
    ),
    'spliters', (
      select jsonb_agg(0 order by idx)
      from generate_series(1, fibers_input) as idx
    )
  ) || case
    when side_input is null then '{}'::jsonb
    else jsonb_build_object('side', side_input)
  end;
$$;

create or replace function pg_temp.demo_switch_json(
  switch_id bigint,
  name_input text,
  model_input text,
  ports_input int
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'id', switch_id,
    'name', name_input,
    'model', model_input,
    'ports', ports_input,
    'port_types', (
      select jsonb_agg(case
        when idx <= 2 then 'uplink'
        when idx % 8 = 0 then 'reserved'
        else 'client'
      end order by idx)
      from generate_series(1, ports_input) as idx
    ),
    'port_comments', (
      select jsonb_agg(case
        when idx <= 2 then 'магистраль'
        when idx % 8 = 0 then 'резерв'
        else ''
      end order by idx)
      from generate_series(1, ports_input) as idx
    )
  );
$$;

create or replace function pg_temp.demo_anchor_json(
  type_input text,
  entity_id_input bigint,
  name_input text,
  subtitle_input text,
  location_input text,
  lat_input double precision,
  lng_input double precision
)
returns jsonb
language sql
as $$
  select jsonb_build_object(
    'type', type_input,
    'entity_id', entity_id_input,
    'name', name_input,
    'subtitle', subtitle_input,
    'location', location_input,
    'lat', lat_input,
    'lng', lng_input
  );
$$;

create or replace procedure pg_temp.demo_upsert_user(
  user_id uuid,
  email_input text,
  full_name_input text,
  position_input text,
  password_input text
)
language plpgsql
as $$
begin
  insert into auth.users (
    instance_id,
    id,
    aud,
    role,
    email,
    encrypted_password,
    email_confirmed_at,
    raw_app_meta_data,
    raw_user_meta_data,
    created_at,
    updated_at,
    confirmation_token,
    email_change,
    email_change_token_new,
    recovery_token
  )
  values (
    '00000000-0000-0000-0000-000000000000',
    user_id,
    'authenticated',
    'authenticated',
    lower(email_input),
    crypt(password_input, gen_salt('bf')),
    timezone('utc', now()),
    jsonb_build_object('provider', 'email', 'providers', array['email']),
    jsonb_build_object('full_name', full_name_input, 'position', position_input),
    timezone('utc', now()),
    timezone('utc', now()),
    '',
    '',
    '',
    ''
  )
  on conflict (id) do update
  set
    email = excluded.email,
    encrypted_password = excluded.encrypted_password,
    email_confirmed_at = coalesce(auth.users.email_confirmed_at, excluded.email_confirmed_at),
    raw_app_meta_data = excluded.raw_app_meta_data,
    raw_user_meta_data = excluded.raw_user_meta_data,
    updated_at = timezone('utc', now());

  insert into public.profiles (id, email, full_name, position)
  values (user_id, lower(email_input), full_name_input, position_input::public.employee_position)
  on conflict (id) do update
  set
    email = excluded.email,
    full_name = excluded.full_name,
    position = excluded.position;

  if exists (
    select 1
    from information_schema.columns
    where table_schema = 'auth'
      and table_name = 'identities'
      and column_name = 'provider_id'
  ) then
    execute $sql$
      insert into auth.identities (
        provider_id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
      )
      values (
        $1,
        $2,
        jsonb_build_object(
          'sub', $2::text,
          'email', $1,
          'email_verified', true,
          'phone_verified', false
        ),
        'email',
        timezone('utc', now()),
        timezone('utc', now()),
        timezone('utc', now())
      )
      on conflict (provider_id, provider) do update
      set
        user_id = excluded.user_id,
        identity_data = excluded.identity_data,
        updated_at = timezone('utc', now())
    $sql$ using lower(email_input), user_id;
  else
    execute $sql$
      insert into auth.identities (
        id,
        user_id,
        identity_data,
        provider,
        last_sign_in_at,
        created_at,
        updated_at
      )
      values (
        $2::text,
        $2,
        jsonb_build_object(
          'sub', $2::text,
          'email', $1,
          'email_verified', true,
          'phone_verified', false
        ),
        'email',
        timezone('utc', now()),
        timezone('utc', now()),
        timezone('utc', now())
      )
      on conflict (id) do update
      set
        user_id = excluded.user_id,
        identity_data = excluded.identity_data,
        updated_at = timezone('utc', now())
    $sql$ using lower(email_input), user_id;
  end if;
end;
$$;

do $$
declare
  demo_slug constant text := 'demo-fiber-city';
  demo_password constant text := 'DemoNetInfra2026!';
  demo_company_id uuid;
  owner_id uuid := pg_temp.demo_user_id_for('demo.owner@netinfra.local');
  engineer_id uuid := pg_temp.demo_user_id_for('demo.engineer@netinfra.local');
  installer1_id uuid := pg_temp.demo_user_id_for('demo.installer1@netinfra.local');
  installer2_id uuid := pg_temp.demo_user_id_for('demo.installer2@netinfra.local');
  dispatch_id uuid := pg_temp.demo_user_id_for('demo.dispatch@netinfra.local');
  actor_email constant text := 'demo.owner@netinfra.local';
  actor_name constant text := 'Алексей Морозов';
  now_text text := timezone('utc', now())::text;
  task_ids bigint[] := array[1001, 1002, 1003, 1004, 1005, 1006];
  districts text[] := array['Северный контур', 'Центральное кольцо', 'Южная линия', 'Промышленная зона'];
  i int;
  cabinet_id bigint;
  muff_id bigint;
  pon_id bigint;
  route_id bigint;
  lat double precision;
  lng double precision;
  task_id bigint;
  start_anchor jsonb;
  end_anchor jsonb;
begin
  call pg_temp.demo_upsert_user(owner_id, 'demo.owner@netinfra.local', 'Алексей Морозов', 'Chief Engineer', demo_password);
  call pg_temp.demo_upsert_user(engineer_id, 'demo.engineer@netinfra.local', 'Мария Волкова', 'Engineer', demo_password);
  call pg_temp.demo_upsert_user(installer1_id, 'demo.installer1@netinfra.local', 'Илья Соколов', 'Installer', demo_password);
  call pg_temp.demo_upsert_user(installer2_id, 'demo.installer2@netinfra.local', 'Денис Орлов', 'Installer', demo_password);
  call pg_temp.demo_upsert_user(dispatch_id, 'demo.dispatch@netinfra.local', 'Наталья Ким', 'Engineer', demo_password);

  delete from public.companies where slug = demo_slug;

  insert into public.companies (name, slug, owner_user_id)
  values ('Demo Fiber City', demo_slug, owner_id)
  returning id into demo_company_id;

  insert into public.company_members (company_id, user_id, role)
  values
    (demo_company_id, owner_id, 'owner'),
    (demo_company_id, engineer_id, 'admin'),
    (demo_company_id, installer1_id, 'member'),
    (demo_company_id, installer2_id, 'member'),
    (demo_company_id, dispatch_id, 'member');

  insert into public.company_module_records (
    company_id,
    module_key,
    record_id,
    task_id,
    payload,
    deleted,
    updated_at,
    synced_at,
    updated_by_user_id
  )
  select
    demo_company_id,
    'projects',
    task_record_id,
    null,
    jsonb_build_object(
      'id', task_record_id,
      'name', case task_record_id
        when 1001 then 'Аудит северного магистрального кольца'
        when 1002 then 'Подключение ЖК Северный Берег'
        when 1003 then 'Резервирование PON-сегмента квартала 17'
        when 1004 then 'Перенос абонентов с временной линии'
        when 1005 then 'Маркировка шкафов центрального узла'
        else 'Проверка документации после выезда'
      end,
      'description', case task_record_id
        when 1001 then 'Проверить магистральные муфты, актуализировать трассы и сверить подписи волокон.'
        when 1002 then 'Завести новые PON-боксы, связать их с маршрутом и шкафами доступа.'
        when 1003 then 'Показать резервные волокна, сплиттеры и точки переключения на карте.'
        when 1004 then 'Закрыть временные подключения и перенести абонентов на постоянную трассу.'
        when 1005 then 'Сверить оборудование, порты и комментарии в сетевых шкафах.'
        else 'Проверить, что все изменения выезда попали в рабочую область.'
      end,
      'created_by_user_id', owner_id::text,
      'created_by_email', actor_email,
      'created_by_name', actor_name,
      'assignees', jsonb_build_array(
        pg_temp.demo_employee_json(engineer_id, 'demo.engineer@netinfra.local', 'Мария Волкова', 'Engineer'),
        pg_temp.demo_employee_json(installer1_id, 'demo.installer1@netinfra.local', 'Илья Соколов', 'Installer'),
        pg_temp.demo_employee_json(installer2_id, 'demo.installer2@netinfra.local', 'Денис Орлов', 'Installer')
      ),
      'work_log', jsonb_build_array(
        jsonb_build_object('at', timezone('utc', now()) - interval '3 days', 'kind', 'Создана задача', 'summary', 'Определены объекты и зона работ'),
        jsonb_build_object('at', timezone('utc', now()) - interval '2 days', 'kind', 'Добавлены объекты', 'summary', 'Шкафы, муфты и маршруты связаны с задачей'),
        jsonb_build_object('at', timezone('utc', now()) - interval '1 day', 'kind', 'Проверка', 'summary', 'Команда сверила ключевые соединения')
      ),
      'completed', task_record_id in (1001, 1004),
      'verified', task_record_id = 1001,
      'archived', false,
      'updated_at', now_text,
      'updated_by', actor_email
    ),
    false,
    timezone('utc', now()),
    timezone('utc', now()),
    owner_id
  from unnest(task_ids) as project_seed(task_record_id);

  for i in 1..24 loop
    cabinet_id := 2000 + i;
    lat := 44.9521 + ((i - 1) / 6) * 0.006 + ((i - 1) % 3) * 0.0009;
    lng := 34.1024 + ((i - 1) % 6) * 0.0065;
    task_id := task_ids[((i - 1) % array_length(task_ids, 1)) + 1];

    insert into public.company_module_records (company_id, module_key, record_id, task_id, payload, deleted, updated_at, synced_at, updated_by_user_id)
    values (
      demo_company_id,
      'network_cabinet',
      cabinet_id,
      task_id,
      jsonb_build_object(
        'id', cabinet_id,
        'name', 'ШК-' || lpad(i::text, 2, '0') || ' / ' || districts[((i - 1) % 4) + 1],
        'location', 'ул. Демонстрационная, ' || (10 + i)::text,
        'comment', 'Демо-шкаф доступа: питание, uplink, абонентские порты и резервные волокна.',
        'location_lat', lat,
        'location_lng', lng,
        'created_by', actor_email,
        'updated_by', actor_email,
        'updated_at', now_text,
        'switches', jsonb_build_array(
          pg_temp.demo_switch_json(cabinet_id * 10 + 1, 'Access SW-' || lpad(i::text, 2, '0'), 'SNR-S2985G-24T', 24),
          pg_temp.demo_switch_json(cabinet_id * 10 + 2, 'PON OLT shelf-' || lpad(i::text, 2, '0'), 'BDCOM GP3600-08', 8)
        ),
        'cables', jsonb_build_array(
          pg_temp.demo_cable_json(cabinet_id * 10 + 101, 'Ввод ОК-' || lpad(i::text, 2, '0') || '-A', 24),
          pg_temp.demo_cable_json(cabinet_id * 10 + 102, 'Абонентский жгут-' || lpad(i::text, 2, '0'), 12)
        ),
        'connections', jsonb_build_array(
          jsonb_build_object('cable1', cabinet_id * 10 + 101, 'fiber1', 0, 'switch2', cabinet_id * 10 + 1, 'port2', 0),
          jsonb_build_object('cable1', cabinet_id * 10 + 101, 'fiber1', 1, 'switch2', cabinet_id * 10 + 1, 'port2', 1),
          jsonb_build_object('switch1', cabinet_id * 10 + 1, 'port1', 2, 'switch2', cabinet_id * 10 + 2, 'port2', 0)
        )
      ),
      false,
      timezone('utc', now()),
      timezone('utc', now()),
      owner_id
    );
  end loop;

  for i in 1..18 loop
    muff_id := 3000 + i;
    lat := 44.9505 + ((i - 1) / 6) * 0.0072 + ((i - 1) % 2) * 0.0011;
    lng := 34.1008 + ((i - 1) % 6) * 0.0068;
    task_id := task_ids[((i - 1) % array_length(task_ids, 1)) + 1];

    insert into public.company_module_records (company_id, module_key, record_id, task_id, payload, deleted, updated_at, synced_at, updated_by_user_id)
    values (
      demo_company_id,
      'muff_notebook',
      muff_id,
      task_id,
      jsonb_build_object(
        'id', muff_id,
        'name', 'МФ-' || lpad(i::text, 2, '0') || ' магистральная',
        'district', districts[((i - 1) % 4) + 1],
        'location', 'колодец K-' || (120 + i)::text,
        'comment', 'Демо-муфта: входящая магистраль, отходящий сегмент и резервные волокна.',
        'is_pon_box', false,
        'location_lat', lat,
        'location_lng', lng,
        'created_by', actor_email,
        'updated_by', actor_email,
        'updated_at', now_text,
        'cables', jsonb_build_array(
          pg_temp.demo_cable_json(muff_id * 10 + 1, 'Магистраль IN-' || lpad(i::text, 2, '0'), 24, 0),
          pg_temp.demo_cable_json(muff_id * 10 + 2, 'Магистраль OUT-' || lpad(i::text, 2, '0'), 24, 1),
          pg_temp.demo_cable_json(muff_id * 10 + 3, 'Ответвление PON-' || lpad(i::text, 2, '0'), 12, 1)
        ),
        'splitters', jsonb_build_array(
          jsonb_build_object('id', muff_id * 100 + 1, 'name', 'Splitter 1:8 A', 'ratio', 8, 'side', 1, 'orientation', 'vertical')
        ),
        'connections', jsonb_build_array(
          jsonb_build_object('endpoint1', jsonb_build_object('cableId', muff_id * 10 + 1, 'fiberIndex', 0), 'endpoint2', jsonb_build_object('cableId', muff_id * 10 + 2, 'fiberIndex', 0)),
          jsonb_build_object('endpoint1', jsonb_build_object('cableId', muff_id * 10 + 1, 'fiberIndex', 1), 'endpoint2', jsonb_build_object('splitterId', muff_id * 100 + 1, 'kind', 'input', 'index', 0)),
          jsonb_build_object('endpoint1', jsonb_build_object('splitterId', muff_id * 100 + 1, 'kind', 'output', 'index', 0), 'endpoint2', jsonb_build_object('cableId', muff_id * 10 + 3, 'fiberIndex', 0))
        )
      ),
      false,
      timezone('utc', now()),
      timezone('utc', now()),
      owner_id
    );
  end loop;

  for i in 1..12 loop
    pon_id := 4000 + i;
    lat := 44.9540 + ((i - 1) / 4) * 0.0058 + ((i - 1) % 2) * 0.0012;
    lng := 34.1050 + ((i - 1) % 4) * 0.0091;
    task_id := task_ids[((i + 1) % array_length(task_ids, 1)) + 1];

    insert into public.company_module_records (company_id, module_key, record_id, task_id, payload, deleted, updated_at, synced_at, updated_by_user_id)
    values (
      demo_company_id,
      'muff_notebook',
      pon_id,
      task_id,
      jsonb_build_object(
        'id', pon_id,
        'name', 'PON-' || lpad(i::text, 2, '0') || ' подъездный бокс',
        'district', districts[((i - 1) % 4) + 1],
        'location', 'ЖК Fiber City, секция ' || ((i - 1) % 6 + 1)::text,
        'comment', 'Демо PON-бокс с абонентскими выходами и резервом.',
        'is_pon_box', true,
        'location_lat', lat,
        'location_lng', lng,
        'created_by', actor_email,
        'updated_by', actor_email,
        'updated_at', now_text,
        'cables', jsonb_build_array(
          pg_temp.demo_cable_json(pon_id * 10 + 1, 'PON feeder-' || lpad(i::text, 2, '0'), 12, 0),
          pg_temp.demo_cable_json(pon_id * 10 + 2, 'Drop bundle-' || lpad(i::text, 2, '0'), 8, 1)
        ),
        'splitters', jsonb_build_array(
          jsonb_build_object('id', pon_id * 100 + 1, 'name', 'Splitter 1:8', 'ratio', 8, 'side', 1, 'orientation', 'horizontal')
        ),
        'connections', jsonb_build_array(
          jsonb_build_object('endpoint1', jsonb_build_object('cableId', pon_id * 10 + 1, 'fiberIndex', 0), 'endpoint2', jsonb_build_object('splitterId', pon_id * 100 + 1, 'kind', 'input', 'index', 0)),
          jsonb_build_object('endpoint1', jsonb_build_object('splitterId', pon_id * 100 + 1, 'kind', 'output', 'index', 0), 'endpoint2', jsonb_build_object('cableId', pon_id * 10 + 2, 'fiberIndex', 0)),
          jsonb_build_object('endpoint1', jsonb_build_object('splitterId', pon_id * 100 + 1, 'kind', 'output', 'index', 1), 'endpoint2', jsonb_build_object('cableId', pon_id * 10 + 2, 'fiberIndex', 1))
        )
      ),
      false,
      timezone('utc', now()),
      timezone('utc', now()),
      owner_id
    );
  end loop;

  for i in 1..30 loop
    route_id := 5000 + i;
    task_id := task_ids[((i + 2) % array_length(task_ids, 1)) + 1];

    if i <= 18 then
      start_anchor := pg_temp.demo_anchor_json(
        'muff',
        3000 + i,
        'МФ-' || lpad(i::text, 2, '0') || ' магистральная',
        'Муфта',
        'колодец K-' || (120 + i)::text,
        44.9505 + ((i - 1) / 6) * 0.0072 + ((i - 1) % 2) * 0.0011,
        34.1008 + ((i - 1) % 6) * 0.0068
      );
      end_anchor := pg_temp.demo_anchor_json(
        'cabinet',
        2000 + ((i - 1) % 24 + 1),
        'ШК-' || lpad(((i - 1) % 24 + 1)::text, 2, '0'),
        'Сетевой шкаф',
        'ул. Демонстрационная, ' || (10 + ((i - 1) % 24 + 1))::text,
        44.9521 + ((((i - 1) % 24)) / 6) * 0.006 + ((((i - 1) % 24)) % 3) * 0.0009,
        34.1024 + ((((i - 1) % 24)) % 6) * 0.0065
      );
    else
      start_anchor := pg_temp.demo_anchor_json(
        'cabinet',
        2000 + ((i - 1) % 24 + 1),
        'ШК-' || lpad(((i - 1) % 24 + 1)::text, 2, '0'),
        'Сетевой шкаф',
        'ул. Демонстрационная, ' || (10 + ((i - 1) % 24 + 1))::text,
        44.9521 + ((((i - 1) % 24)) / 6) * 0.006 + ((((i - 1) % 24)) % 3) * 0.0009,
        34.1024 + ((((i - 1) % 24)) % 6) * 0.0065
      );
      end_anchor := pg_temp.demo_anchor_json(
        'pon_box',
        4000 + ((i - 19) % 12 + 1),
        'PON-' || lpad(((i - 19) % 12 + 1)::text, 2, '0') || ' подъездный бокс',
        'PON box',
        'ЖК Fiber City, секция ' || (((i - 19) % 6) + 1)::text,
        44.9540 + (((i - 19) % 12) / 4) * 0.0058 + (((i - 19) % 12) % 2) * 0.0012,
        34.1050 + (((i - 19) % 12) % 4) * 0.0091
      );
    end if;

    insert into public.company_module_records (company_id, module_key, record_id, task_id, payload, deleted, updated_at, synced_at, updated_by_user_id)
    values (
      demo_company_id,
      'cable_lines',
      route_id,
      task_id,
      jsonb_build_object(
        'id', route_id,
        'name', case when i <= 18 then 'Магистральный участок ' else 'Распределительный маршрут ' end || lpad(i::text, 2, '0'),
        'note', case when i <= 18 then '24 волокна, резерв 30%, трасса вдоль коллекторов.' else 'PON распределение до подъездного бокса, контроль запаса кабеля.' end,
        'start_anchor', start_anchor,
        'end_anchor', end_anchor,
        'route_points', jsonb_build_array(
          jsonb_build_object('lat', (start_anchor ->> 'lat')::double precision, 'lng', (start_anchor ->> 'lng')::double precision),
          jsonb_build_object(
            'lat', ((start_anchor ->> 'lat')::double precision + (end_anchor ->> 'lat')::double precision) / 2 + 0.0015,
            'lng', ((start_anchor ->> 'lng')::double precision + (end_anchor ->> 'lng')::double precision) / 2 - 0.0012
          ),
          jsonb_build_object('lat', (end_anchor ->> 'lat')::double precision, 'lng', (end_anchor ->> 'lng')::double precision)
        ),
        'updated_at', now_text
      ),
      false,
      timezone('utc', now()),
      timezone('utc', now()),
      owner_id
    );
  end loop;

  raise notice 'Demo company % seeded. Login: demo.owner@netinfra.local / %', demo_company_id, demo_password;
end $$;
