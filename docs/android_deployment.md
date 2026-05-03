# Android Build and Deployment

The project now has a GitHub Actions workflow for signed Android builds:

- [.github/workflows/deploy-android.yml](../.github/workflows/deploy-android.yml)
- [scripts/build_android.sh](../scripts/build_android.sh)
- [scripts/build_android.ps1](../scripts/build_android.ps1)

## What the Workflow Does

On pushes to `main`, `master`, tags like `v*` or `android-v*`, and manual `workflow_dispatch`, it:

- restores the Android upload keystore from GitHub Secrets
- runs `flutter pub get`
- runs `flutter analyze`
- runs `flutter test`
- builds signed release APK and/or AAB
- uploads release artifacts
- deploys APK to Firebase App Distribution on release tags or manual Firebase runs when secrets are configured
- deploys AAB to Google Play on release tags or manual Google Play runs when secrets are configured

## Required GitHub Secrets

These are required for every Android release build:

```text
SUPABASE_URL
SUPABASE_ANON_KEY
ANDROID_KEYSTORE_BASE64
ANDROID_KEYSTORE_PASSWORD
ANDROID_KEY_ALIAS
ANDROID_KEY_PASSWORD
```

Create `ANDROID_KEYSTORE_BASE64` from the upload keystore:

```bash
base64 -w 0 android/app/net_infra_saas_upload.keystore
```

PowerShell alternative:

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/net_infra_saas_upload.keystore"))
```

## Optional Firebase App Distribution

To deploy APK builds to Firebase App Distribution, add:

```text
FIREBASE_ANDROID_APP_ID
FIREBASE_TOKEN
```

Optional repository variable:

```text
FIREBASE_ANDROID_GROUPS
```

If `FIREBASE_ANDROID_GROUPS` is not set, the workflow uses `testers`.

## Optional Google Play

To deploy AAB builds to Google Play, add:

```text
GOOGLE_PLAY_SERVICE_ACCOUNT_JSON
```

The workflow publishes package `io.netinfra.saas`. Manual runs can choose the target track:

- `internal`
- `alpha`
- `beta`
- `production`

## Local Release Build

PowerShell:

```powershell
$env:SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
$env:SUPABASE_ANON_KEY="YOUR_SUPABASE_ANON_KEY"
$env:ANDROID_BUILD_TARGET="both"
.\scripts\build_android.ps1
```

Bash:

```bash
export SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
export SUPABASE_ANON_KEY="YOUR_SUPABASE_ANON_KEY"
export ANDROID_BUILD_TARGET="both"
bash scripts/build_android.sh
```

Outputs:

```text
build/app/outputs/flutter-apk/app-release.apk
build/app/outputs/bundle/release/app-release.aab
```
