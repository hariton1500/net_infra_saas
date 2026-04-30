# net_infra_saas

Flutter-приложение с авторизацией через Supabase для компаний и их сотрудников.

## Маркетинговая документация

Для презентации сервиса, лендинга и партнёрских материалов используйте:

- [Multilingual Marketing Overview](docs/marketing_overview.md)
- [Landing Page Copy](docs/landing_page_copy.md)
- [Commercial Description](docs/commercial_description.md)
- [Android Release Kit](docs/android_release_kit.md)
- [Android Google Play Package](docs/android_google_play_package.md)
- [Android Screenshot Shot List](docs/android_screenshot_shotlist.md)
- [Promo Video Voice-over](docs/promo_video_voiceover.md)

## Что уже реализовано

- вход и регистрация по email/password через Supabase Auth
- восстановление активной сессии при повторном запуске
- onboarding владельца компании после регистрации
- multi-tenant база с таблицами `profiles`, `companies`, `company_members`
- базовые RLS policy для изоляции данных между компаниями

## 1. Применить SQL-миграции в Supabase

Выполните файлы миграций из папки [supabase/migrations](supabase/migrations) в SQL Editor вашего Supabase-проекта по порядку.

Эти миграции создают:

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

## 4. Собрать и опубликовать web

Web-сборка и автодеплой в Cloudflare Pages и REG.RU описаны в [docs/web_deployment.md](docs/web_deployment.md).

## Как работает текущий flow

1. Владелец компании регистрируется по email/password.
2. Если email confirmation выключен, компания создаётся сразу.
3. Если email confirmation включён, пользователь подтверждает email, затем входит и завершает создание компании.
4. После входа сотрудник попадает в своё рабочее пространство компании.

## Что логично сделать следующим шагом

- приглашения сотрудников в компанию
- экран управления пользователями и ролями
- отдельные таблицы бизнес-данных с привязкой к `company_id`
- guard для admin-only маршрутов
