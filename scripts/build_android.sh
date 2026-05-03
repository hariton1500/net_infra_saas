#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${SUPABASE_URL:-}" ]]; then
  echo "SUPABASE_URL is required" >&2
  exit 1
fi

if [[ -z "${SUPABASE_ANON_KEY:-}" ]]; then
  echo "SUPABASE_ANON_KEY is required" >&2
  exit 1
fi

ANDROID_BUILD_TARGET="${ANDROID_BUILD_TARGET:-appbundle}"

build_args=(
  --release
  --dart-define="SUPABASE_URL=${SUPABASE_URL}"
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
)

if [[ -n "${BUILD_NAME:-}" ]]; then
  build_args+=(--build-name="${BUILD_NAME}")
fi

if [[ -n "${BUILD_NUMBER:-}" ]]; then
  build_args+=(--build-number="${BUILD_NUMBER}")
fi

case "${ANDROID_BUILD_TARGET}" in
  apk)
    flutter build apk "${build_args[@]}"
    ;;
  appbundle)
    flutter build appbundle "${build_args[@]}"
    ;;
  both)
    flutter build apk "${build_args[@]}"
    flutter build appbundle "${build_args[@]}"
    ;;
  *)
    echo "ANDROID_BUILD_TARGET must be apk, appbundle, or both" >&2
    exit 1
    ;;
esac
