#!/usr/bin/env bash
# Open a subshell with GIT_DIR and GIT_WORK_TREE set for a review store.
#
# Usage:
#   review-shell [<pr-slug>]

set -euo pipefail
_RV_SELF="${BASH_SOURCE[0]}"; while [ -L "$_RV_SELF" ]; do _RV_SELF="$(readlink "$_RV_SELF")"; done; source "$(cd "$(dirname "$_RV_SELF")" && pwd)/review-lib.sh"

slug=$(_rv_resolve_slug "${1:-}")
store=$(_rv_store_dir "$slug")
project_dir="$(_rv_project_dir)"

if [[ ! -d "$store/repo" ]]; then
  echo "review-shell: no store at $store" >&2
  exit 1
fi

# Refresh intent-to-add markers for any untracked files that appeared since
# the store was created (e.g. after a `git pull` brought in new PR files).
# This ensures `git diff HEAD` continues to show the full unreviewed diff.
while IFS= read -r -d '' f; do
  git --git-dir="$store/repo" --work-tree="$project_dir" \
      add --intent-to-add -- "$f" 2>/dev/null || true
done < <(git --git-dir="$store/repo" --work-tree="$project_dir" \
           ls-files --others --exclude-standard -z 2>/dev/null)

# Pick the user's shell; default zsh on macOS.
shell_bin="${SHELL:-/bin/zsh}"

export GIT_DIR="$store/repo"
export GIT_WORK_TREE="$project_dir"
export REVIEW_SLUG="$slug"
export REVIEW_STORE="$store"

# Custom prompt prefix — works for zsh and bash. Avoid clobbering user prompts:
# we set RPS1 (zsh) or PS1 prefix (bash) only for the spawned shell.
prompt_prefix="(review:${slug}) "

case "$(basename "$shell_bin")" in
  zsh)
    # Use a tmp ZDOTDIR so we can inject the prompt without touching the user's .zshrc.
    tmpdir=$(mktemp -d -t review-shell-XXXXXX)
    trap 'rm -rf "$tmpdir"' EXIT
    cat > "$tmpdir/.zshrc" <<EOF
[[ -f "\$HOME/.zshrc" ]] && source "\$HOME/.zshrc"
PROMPT="%F{cyan}${prompt_prefix}%f\$PROMPT"
EOF
    ZDOTDIR="$tmpdir" exec "$shell_bin" -i
    ;;
  bash)
    tmprc=$(mktemp -t review-shell-bashrc-XXXXXX)
    trap 'rm -f "$tmprc"' EXIT
    cat > "$tmprc" <<EOF
[[ -f "\$HOME/.bashrc" ]] && source "\$HOME/.bashrc"
PS1="\\[\\e[36m\\]${prompt_prefix}\\[\\e[0m\\]\$PS1"
EOF
    exec "$shell_bin" --rcfile "$tmprc" -i
    ;;
  *)
    echo "review-shell: unknown shell '$shell_bin'; entering with no prompt prefix" >&2
    exec "$shell_bin" -i
    ;;
esac
