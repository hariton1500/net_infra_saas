# Android Release Kit

This document prepares the project for Android publication and explains what is still required before the first Google Play release.

## Current State

- Android platform scaffold exists in [android](../android)
- App label is set to `Net Infra SaaS`
- Android package id is set to `io.netinfra.saas`
- Release signing is configured through `android/key.properties`
- Automated signed builds are configured in [.github/workflows/deploy-android.yml](../.github/workflows/deploy-android.yml)
- Google Play text and media preparation files are available under [distribution/android/google_play](../distribution/android/google_play)

## Must Change Before Publishing

### 1. Confirm final application ID

The current `namespace` and `applicationId` are `io.netinfra.saas`. Keep this value for Google Play once the first release is uploaded.

### 2. Add release secrets to CI

Set the required GitHub Secrets from [android_deployment.md](android_deployment.md) before running the Android deployment workflow.

### 3. Replace the launcher icon if needed

The Android app currently uses the default generated launcher icon. For store publication, prepare a production icon and regenerate Android mipmaps.

### 4. Build the release bundle

Recommended command when signing is configured:

```bash
flutter build appbundle --release
```

## Google Play Materials Prepared

Use this folder as the release package:

- [distribution/android/google_play](../distribution/android/google_play)

Included:

- store descriptions
- screenshot plan
- promo video storyboard
- voice-over script
- publication checklist
- media folder structure

## Media Requirements

### Phone screenshots

Recommended minimum set:

- 6 to 8 screenshots
- portrait orientation
- show real product workflows, not placeholder screens

### Promo video

Recommended format:

- 30 to 60 seconds
- focused on operational problems and practical workflow value
- office plus field coordination message

## Suggested Screenshot Set

1. Sign in and company workspace entry
2. Infrastructure map overview
3. Active task visibility
4. Muff notebook and field data
5. Network cabinet management
6. Route or connection workflow
7. Team coordination or role-based view
8. Mobile-friendly or field-ready positioning screen

## Suggested Release Order

1. Finalize package id
2. Add production icon
3. Set signing config
4. Capture final screenshots from release UI
5. Record promo video from storyboard
6. Build `.aab`
7. Upload store assets and text to Google Play Console

## Important Note

This repository now contains the Android release automation structure, but the actual publication still requires:

- GitHub Secrets for signing and Supabase dart-defines
- Firebase or Google Play credentials if automatic deployment is enabled
- final real screenshots
- final exported promo video
