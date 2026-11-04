#!/usr/bin/env bash
# Prints Markdown release notes: the commit titles since the previous version tag.
# Usage: scripts/release-notes.sh [ref]   (default: HEAD; in CI the tag being released)
# Needs full history and tags (actions/checkout with fetch-depth: 0).
set -euo pipefail

REF="${1:-HEAD}"
REPO_URL="${REPO_URL:-https://github.com/ja1984/courier}"
PREVIOUS="$(git describe --tags --abbrev=0 --match 'v*' "$REF^" 2>/dev/null || true)"
RANGE="${PREVIOUS:+$PREVIOUS..}$REF"

echo "## What's new"
echo
CHANGES="$(git log --no-merges --pretty='- %s' "$RANGE")"
echo "${CHANGES:-- Maintenance release}"
echo
if [[ -n "$PREVIOUS" ]]; then
  echo "**Full changelog:** $REPO_URL/compare/$PREVIOUS...$REF"
else
  echo "**Full changelog:** $REPO_URL/commits/$REF"
fi
