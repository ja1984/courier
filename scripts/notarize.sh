#!/usr/bin/env bash
# Notarizes a .zip or .dmg with an App Store Connect API key and waits for the result.
# Usage: scripts/notarize.sh <file>
# Env: NOTARY_KEY_PATH (the .p8), NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID
set -euo pipefail

FILE="${1:?usage: notarize.sh <file>}"
AUTH=(--key "${NOTARY_KEY_PATH:?}" --key-id "${NOTARY_API_KEY_ID:?}" --issuer "${NOTARY_API_ISSUER_ID:?}")
RESULT="$(mktemp)"
trap 'rm -f "$RESULT"' EXIT

# Don't stop on a non-zero exit here: the status check below fetches Apple's log first.
xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait --timeout 30m --output-format json | tee "$RESULT" || true
echo

STATUS="$(plutil -extract status raw "$RESULT" 2>/dev/null || echo "no response")"
if [[ "$STATUS" != "Accepted" ]]; then
  if ID="$(plutil -extract id raw "$RESULT" 2>/dev/null)"; then
    xcrun notarytool log "$ID" "${AUTH[@]}" || true
  fi
  echo "::error::Notarization of $(basename "$FILE") failed: $STATUS" >&2
  exit 1
fi
echo "Notarized $(basename "$FILE")"
