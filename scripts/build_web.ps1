$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:SUPABASE_URL)) {
  Write-Error "SUPABASE_URL is required"
}

if ([string]::IsNullOrWhiteSpace($env:SUPABASE_ANON_KEY)) {
  Write-Error "SUPABASE_ANON_KEY is required"
}

$baseHref = if ([string]::IsNullOrWhiteSpace($env:BASE_HREF)) {
  "/"
} else {
  $env:BASE_HREF
}

flutter build web `
  --release `
  --base-href="$baseHref" `
  --dart-define="SUPABASE_URL=$env:SUPABASE_URL" `
  --dart-define="SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY"

$appHtml = "build/web/app.html"
if (Test-Path $appHtml) {
  (Get-Content $appHtml -Raw).Replace('$FLUTTER_BASE_HREF', $baseHref) | Set-Content $appHtml
}
