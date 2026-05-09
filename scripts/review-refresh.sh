#!/usr/bin/env bash
# Refresh the working tree from origin and report new outstanding diff.
#
# Usage:
#   review-refresh [<pr-slug>]
#
# Runs `git fetch && git pull --ff-only` in the real repo (must be run from
# the project directory, NOT inside review-shell), then prints the change.

set -euo pipefail
_RV_SELF="${BASH_SOURCE[0]}"; while [ -L "$_RV_SELF" ]; do _RV_SELF="$(readlink "$_RV_SELF")"; done; source "$(cd "$(dirname "$_RV_SELF")" && pwd)/review-lib.sh"

# Reject if invoked inside review-shell — we need the real repo.
if [[ -n "${REVIEW_SLUG:-}" ]]; then
  echo "review-refresh: do not run inside review-shell — exit first, then refresh." >&2
  exit 1
fi

slug=$(_rv_resolve_slug "${1:-}")
store=$(_rv_store_dir "$slug")

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "review-refresh: $PWD is not inside a git repo" >&2
  exit 1
fi

echo "Fetching origin..."
git fetch --quiet
echo "Pulling current branch..."
git pull --ff-only --quiet || {
  echo "review-refresh: pull is not fast-forward; resolve manually." >&2
  exit 1
}

_rv_state_write "$store" "LAST_REFRESHED_AT" "$(_rv_now)"

echo
echo "Outstanding diff after refresh:"
remaining=$(_rv_git "$store" diff --numstat 2>/dev/null || true)
if [[ -z "$remaining" ]]; then
  echo "  (no remaining changes — review complete!)"
else
  echo "$remaining" | awk '{printf "  %-50s  +%s -%s\n", $3, $1, $2}'
fi
