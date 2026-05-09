#!/usr/bin/env bash
# Delete a review store.
#
# Usage:
#   review-end <pr-slug> [--force]

set -euo pipefail
_RV_SELF="${BASH_SOURCE[0]}"; while [ -L "$_RV_SELF" ]; do _RV_SELF="$(readlink "$_RV_SELF")"; done; source "$(cd "$(dirname "$_RV_SELF")" && pwd)/review-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: review-end <pr-slug> [--force]" >&2
  exit 64
fi

slug="$1"
force=""
[[ "${2:-}" == "--force" ]] && force=1

store=$(_rv_store_dir "$slug")
if [[ ! -d "$store" ]]; then
  echo "review-end: no store at $store" >&2
  exit 1
fi

# If review-status would show incomplete coverage, confirm.
if [[ -z "$force" ]]; then
  remaining=$(_rv_git "$store" diff --numstat 2>/dev/null || true)
  remaining_lines=$(awk 'NF >= 3 && $1 ~ /^[0-9]+$/ {a+=$1+$2} END {print a+0}' <<<"$remaining")
  if [[ "$remaining_lines" -gt 0 ]]; then
    echo "Review for '$slug' has $remaining_lines unreviewed line(s) remaining."
    read -r -p "Delete anyway? [y/N] " ans
    case "$ans" in
      y|Y|yes|YES) ;;
      *) echo "Aborted."; exit 1 ;;
    esac
  fi
fi

rm -rf "$store"
echo "Deleted review store: $store"

# Clean up the project root if empty.
root=$(_rv_project_root)
if [[ -d "$root" ]] && [[ -z "$(ls -A "$root" 2>/dev/null)" ]]; then
  rmdir "$root"
fi
