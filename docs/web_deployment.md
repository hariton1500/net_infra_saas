# Web deployment

Проект собирается как статическое Flutter web-приложение в `build/web` и может публиковаться одновременно в Cloudflare Pages и на хостинг REG.RU.

## Локальная сборка

macOS/Linux:

```bash
SUPABASE_URL="https://YOUR_PROJECT.supabase.co" \
SUPABASE_ANON_KEY="YOUR_SUPABASE_ANON_KEY" \
bash scripts/build_web.sh
```

Windows PowerShell:

```powershell
$env:SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
$env:SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY"
powershell -ExecutionPolicy Bypass -File scripts/build_web.ps1
```

Если приложение размещается не в корне домена, задайте `BASE_HREF`, например:

macOS/Linux:

```bash
BASE_HREF="/app/" \
SUPABASE_URL="https://YOUR_PROJECT.supabase.co" \
SUPABASE_ANON_KEY="YOUR_SUPABASE_ANON_KEY" \
bash scripts/build_web.sh
```

Windows PowerShell:

```powershell
$env:BASE_HREF = "/app/"
$env:SUPABASE_URL = "https://YOUR_PROJECT.supabase.co"
$env:SUPABASE_ANON_KEY = "YOUR_SUPABASE_ANON_KEY"
powershell -ExecutionPolicy Bypass -File scripts/build_web.ps1
```

## GitHub Actions secrets

Обязательные секреты для сборки:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Секреты для Cloudflare Pages:

- `CLOUDFLARE_ACCOUNT_ID`
- `CLOUDFLARE_API_TOKEN`
- `CLOUDFLARE_PAGES_PROJECT`

Токену Cloudflare нужны права `Account -> Cloudflare Pages -> Edit`.

Секреты для REG.RU:

- `REG_RU_HOST`: IP, домен или технологический домен хостинга
- `REG_RU_USER`: логин хостинга, например `u1234567`
- `REG_RU_SSH_PRIVATE_KEY`: приватный SSH-ключ для деплоя
- `REG_RU_REMOTE_PATH`: каталог сайта на хостинге, например `/var/www/u1234567/data/www/example.ru`
- `REG_RU_PORT`: порт SSH, если отличается от `22`

Для REG.RU нужен тариф с SSH-доступом. На Linux-хостинге REG.RU SSH доступен не на всех тарифах, например Host-Lite его не поддерживает.

## GitHub Actions variables

Опционально можно задать repository variable:

- `WEB_BASE_HREF`: базовый путь приложения, по умолчанию `/`

## Автопубликация

Workflow `.github/workflows/deploy-web.yml` запускается при push в `main` или `master`, а также вручную через `workflow_dispatch`.

Сначала выполняются:

- `flutter pub get`
- `flutter analyze`
- `flutter test`
- `bash scripts/build_web.sh`

Затем один и тот же артефакт `build/web` публикуется:

- в Cloudflare Pages через `cloudflare/wrangler-action`
- на REG.RU через `rsync` по SSH
