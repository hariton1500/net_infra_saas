# net_infra_saas

Flutter-приложение с авторизацией через Supabase для компаний и их сотрудников.

## Что уже реализовано

- вход и регистрация по email/password через Supabase Auth
- восстановление активной сессии при повторном запуске
- onboarding владельца компании после регистрации
- multi-tenant база с таблицами `profiles`, `companies`, `company_members`
- базовые RLS policy для изоляции данных между компаниями

## 1. Применить SQL-миграцию в Supabase

Выполните файлы миграций из папки [supabase/migrations](/Users/hariton/Documents/programs/net_infra_saas/supabase/migrations) в SQL Editor вашего Supabase-проекта по порядку.

Эта миграция создаёт:

- `profiles` для профиля пользователя
- `companies` для компаний
- `company_members` для ролей сотрудников внутри компании
- trigger на `auth.users`
- RPC `create_company_with_owner(...)` для создания первой компании владельца

Отдельная follow-up миграция исправляет RLS policy для `company_members`, чтобы убрать рекурсию при чтении membership.

## 2. Получить параметры проекта Supabase

В Supabase откройте:

- `Project Settings -> API`
- скопируйте `Project URL`
- скопируйте `anon public key`

## 3. Запустить приложение

```bash
/Users/hariton/flutter/bin/flutter pub get
/Users/hariton/flutter/bin/flutter run \
  --dart-define=SUPABASE_URL=https://YOUR_PROJECT.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

## Как работает текущий flow

1. Владелец компании регистрируется по email/password.
2. Если email confirmation выключен, компания создаётся сразу.
3. Если email confirmation включен, пользователь подтверждает email, затем входит и завершает создание компании.
4. После входа сотрудник попадает в своё рабочее пространство компании.

## Что логично сделать следующим шагом

- приглашения сотрудников в компанию
- экран управления пользователями и ролями
- отдельные таблицы бизнес-данных с привязкой к `company_id`
- guard для admin-only маршрутов
