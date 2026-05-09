#!/usr/bin/env bash
# Show a diff of remaining unreviewed code.
#
# Usage:
#   review-remaining [<pr-slug>] [-- <git-diff-args>]
#
# Examples:
#   review-remaining                    # full diff against review HEAD
#   review-remaining pr-123             # for a specific store
#   review-remaining -- --stat          # summary only
#   review-remaining -- src/auth/       # restrict to a path

set -euo pipefail
_RV_SELF="${BASH_SOURCE[0]}"; while [ -L "$_RV_SELF" ]; do _RV_SELF="$(readlink "$_RV_SELF")"; done; source "$(cd "$(dirname "$_RV_SELF")" && pwd)/review-lib.sh"

slug=""
diff_args=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; diff_args=("$@"); break ;;
    -*) diff_args+=("$1"); shift ;;
    *)
      if [[ -z "$slug" ]]; then slug="$1"; else diff_args+=("$1"); fi
      shift
      ;;
  esac
done

slug=$(_rv_resolve_slug "$slug")
store=$(_rv_store_dir "$slug")

# Use plain `git diff` (working vs index) so staged-as-reviewed code is excluded.
_rv_git "$store" diff "${diff_args[@]:-}"
