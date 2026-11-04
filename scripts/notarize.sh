#!/usr/bin/env bash
# Notarizes a .zip or .dmg with an App Store Connect API key and waits for the result.
# A team's first submissions can take much longer than the usual few minutes.
# Usage: scripts/notarize.sh <file>
# Env: NOTARY_KEY_PATH (the .p8), NOTARY_API_KEY_ID, NOTARY_API_ISSUER_ID
set -euo pipefail

FILE="${1:?usage: notarize.sh <file>}"
AUTH=(--key "${NOTARY_KEY_PATH:?}" --key-id "${NOTARY_API_KEY_ID:?}" --issuer "${NOTARY_API_ISSUER_ID:?}")
RESULT="$(mktemp)"
trap 'rm -f "$RESULT"' EXIT

# Don't stop on a non-zero exit here: the status check below fetches Apple's log first.
xcrun notarytool submit "$FILE" "${AUTH[@]}" --wait --timeout 60m --output-format json | tee "$RESULT" || true
echo

# On a timeout or an API error there's no status, only a message.
STATUS="$(plutil -extract status raw "$RESULT" 2>/dev/null || plutil -extract message raw "$RESULT" 2>/dev/null || echo "no response from notarytool")"
if [[ "$STATUS" != "Accepted" ]]; then
  if ID="$(plutil -extract id raw "$RESULT" 2>/dev/null)"; then
    xcrun notarytool log "$ID" "${AUTH[@]}" || true
  fi
  echo "::error::Notarization of $(basename "$FILE") failed: $STATUS" >&2
  exit 1
fi
echo "Notarized $(basename "$FILE")"
