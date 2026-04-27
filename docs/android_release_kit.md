# Android Release Kit

This document prepares the project for Android publication and explains what is still required before the first Google Play release.

## Current State

- Android platform scaffold exists in [android](../android)
- App label is set to `Net Infra SaaS`
- Default Android package id is still `com.example.net_infra_saas`
- Release build is still signed with the debug key and must be replaced before publication
- Google Play text and media preparation files are available under [distribution/android/google_play](../distribution/android/google_play)

## Must Change Before Publishing

### 1. Set final application ID

Update these fields in [android/app/build.gradle.kts](../android/app/build.gradle.kts):

- `namespace`
- `applicationId`

Recommended format:

```text
com.yourcompany.netinfra
```

### 2. Configure release signing

Create a dedicated keystore and connect it to Gradle before uploading an `.aab` to Google Play.

What is still missing:

- release keystore file
- keystore alias
- keystore passwords
- secure local configuration for signing

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

This repository now contains the full release preparation structure, but the actual publication still requires:

- your final signing key
- your final package name
- final real screenshots
- final exported promo video
