# Android Google Play Package

This document contains the exact recommended setup for the first Google Play release.

## Recommended Package Identity

### Recommended `applicationId`

```text
io.netinfra.saas
```

### Recommended `namespace`

```text
io.netinfra.saas
```

This recommendation is already reflected in:

- [android/app/build.gradle.kts](../android/app/build.gradle.kts)

If you already own a company domain and want a more branded identifier, use:

```text
com.yourcompany.netinfra
```

## Recommended Versioning

### Initial release

- `versionName`: `1.0.0`
- `versionCode`: `1`

### Suggested release strategy

- Major release: `2.0.0`
- Feature release: `1.1.0`
- Fix release: `1.0.1`

### Version code policy

Increase `versionCode` by `1` for every upload to Google Play.

Examples:

- `1.0.0+1`
- `1.0.1+2`
- `1.1.0+3`
- `1.1.1+4`

### Where to change it

- [pubspec.yaml](../pubspec.yaml)

Current Flutter format:

```yaml
version: 1.0.0+1
```

## Signing Configuration

The Android project now supports a dedicated release keystore through:

- [android/key.properties.example](../android/key.properties.example)
- [android/app/build.gradle.kts](../android/app/build.gradle.kts)

## How to enable release signing

### 1. Create an upload keystore

Example command:

```bash
keytool -genkeypair -v ^
  -keystore keystore/net_infra_saas-upload-keystore.jks ^
  -keyalg RSA ^
  -keysize 2048 ^
  -validity 10000 ^
  -alias upload
```

### 2. Create local signing config

Copy:

- [android/key.properties.example](../android/key.properties.example)

to:

- `android/key.properties`

Then replace:

- `storeFile`
- `storePassword`
- `keyAlias`
- `keyPassword`

### 3. Keep secrets out of git

Do not commit:

- `android/key.properties`
- keystore files

## Build Commands

### Debug check

```bash
flutter build apk --debug
```

### Release app bundle for Google Play

```bash
flutter build appbundle --release
```

### Expected output

```text
build/app/outputs/bundle/release/app-release.aab
```

## Google Play Console Package Checklist

- final package id confirmed
- keystore created
- `android/key.properties` configured
- release `.aab` built
- store listing uploaded
- screenshots uploaded
- promo video uploaded or linked
- privacy policy added
- test release verified

