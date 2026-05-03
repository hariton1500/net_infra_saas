$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($env:SUPABASE_URL)) {
  Write-Error "SUPABASE_URL is required"
}

if ([string]::IsNullOrWhiteSpace($env:SUPABASE_ANON_KEY)) {
  Write-Error "SUPABASE_ANON_KEY is required"
}

$target = if ([string]::IsNullOrWhiteSpace($env:ANDROID_BUILD_TARGET)) {
  "appbundle"
} else {
  $env:ANDROID_BUILD_TARGET
}

$buildArgs = @(
  "--release",
  "--dart-define=SUPABASE_URL=$env:SUPABASE_URL",
  "--dart-define=SUPABASE_ANON_KEY=$env:SUPABASE_ANON_KEY"
)

if (-not [string]::IsNullOrWhiteSpace($env:BUILD_NAME)) {
  $buildArgs += "--build-name=$env:BUILD_NAME"
}

if (-not [string]::IsNullOrWhiteSpace($env:BUILD_NUMBER)) {
  $buildArgs += "--build-number=$env:BUILD_NUMBER"
}

switch ($target) {
  "apk" {
    flutter build apk @buildArgs
  }
  "appbundle" {
    flutter build appbundle @buildArgs
  }
  "both" {
    flutter build apk @buildArgs
    flutter build appbundle @buildArgs
  }
  default {
    Write-Error "ANDROID_BUILD_TARGET must be apk, appbundle, or both"
  }
}
