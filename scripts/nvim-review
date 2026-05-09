#!/usr/bin/env bash
# Launch nvim configured for PR review:
#   - closes any auto-opened file explorer (neo-tree / nvim-tree)
#   - opens the ReviewSidebar
#
# Must be run from inside a review-shell so $GIT_DIR points at a review store.
#
# Usage:
#   nvim-review                # blank nvim with sidebar
#   nvim-review path/to/file   # opens the file alongside the sidebar

set -euo pipefail

if [[ -z "${GIT_DIR:-}" ]] || [[ "$GIT_DIR" != *"/.review/"* ]]; then
  cat >&2 <<EOF
nvim-review: not in a review-shell.

GIT_DIR must point at a review store (~/.review/...). Start one with:
  review-start <slug>
  review-shell <slug>
  nvim-review
EOF
  exit 1
fi

# We register the close+open as VimEnter autocmds (++once) so they run AFTER
# plugins finish loading. -c registers the autocmds during startup, before
# VimEnter fires, so the order is: register → plugins load → VimEnter → close
# explorer → open sidebar.
exec nvim "$@" \
  -c "autocmd VimEnter * ++once silent! Neotree close" \
  -c "autocmd VimEnter * ++once silent! NvimTreeClose" \
  -c "autocmd VimEnter * ++once ReviewSidebar"
