#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/../../.."
: "${AUDIT_RELEASE_KEEP:?set an existing retained helper-run directory}"
printf '%s\n' 'inert audit fixture; never sent to GitHub' > "$AUDIT_RELEASE_KEEP/payload.zip"
export PATH="$PWD/docs/audits/executive-2026-10-17/mock-bin:/usr/bin:/bin:/mingw64/bin"
bash tools/publish_release.sh v0.4.36 "$AUDIT_RELEASE_KEEP/payload.zip"
if grep -q '^release upload v0.4.36 .* --clobber$' "$AUDIT_RELEASE_KEEP/gh-calls.log" \
  && ! grep -q -- '--json' "$AUDIT_RELEASE_KEEP/gh-calls.log"; then
  echo 'AUDIT RELEASE OBSERVATION CONFIRMED: existing published release is uploaded with --clobber without checking draft state'
else
  echo 'AUDIT RELEASE OBSERVATION FAILED'
  exit 1
fi
