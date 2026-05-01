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

BASE_HREF="${BASE_HREF:-/}"

flutter build web \
  --release \
  --base-href="${BASE_HREF}" \
  --dart-define="SUPABASE_URL=${SUPABASE_URL}" \
  --dart-define="SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}"
