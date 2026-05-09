#!/usr/bin/env bash
# Shared utilities for review scripts. Source this — do not execute directly.

REVIEW_BASE="${REVIEW_BASE:-$HOME/.review}"

_rv_project_dir() {
  echo "${REVIEW_PROJECT_DIR:-$PWD}"
}

_rv_project_hash() {
  _rv_project_dir | md5 | cut -c1-16
}

_rv_project_root() {
  echo "$REVIEW_BASE/$(_rv_project_hash)"
}

_rv_store_dir() {
  local slug="$1"
  echo "$(_rv_project_root)/$slug"
}

# Sanitize a slug: keep alphanumerics, dashes, underscores, dots.
_rv_sanitize_slug() {
  echo "$1" | tr -c '[:alnum:]._-' '-' | sed 's/^-*//;s/-*$//'
}

_rv_list_slugs() {
  local root
  root="$(_rv_project_root)"
  [[ -d "$root" ]] || return 0
  for d in "$root"/*/; do
    [[ -d "${d}repo" ]] || continue
    basename "${d%/}"
  done
}

# Resolve an unambiguous slug for the current project.
_rv_resolve_slug() {
  local slug="${1:-}"
  if [[ -n "$slug" ]]; then
    echo "$slug"
    return 0
  fi
  local slugs=()
  while IFS= read -r s; do slugs+=("$s"); done < <(_rv_list_slugs)
  if [[ ${#slugs[@]} -eq 0 ]]; then
    echo "review-lib: no review stores for $(_rv_project_dir)" >&2
    return 1
  fi
  if [[ ${#slugs[@]} -eq 1 ]]; then
    echo "${slugs[0]}"
    return 0
  fi
  echo "review-lib: multiple review stores; pass <slug> as argument:" >&2
  for s in "${slugs[@]}"; do echo "  - $s" >&2; done
  return 1
}

# Set GIT_DIR / GIT_WORK_TREE for a given slug. Caller must `export` after sourcing.
_rv_setup_env() {
  local slug="$1"
  local store
  store="$(_rv_store_dir "$slug")"
  if [[ ! -d "$store/repo" ]]; then
    echo "review-lib: no review store at $store/repo" >&2
    return 1
  fi
  export GIT_DIR="$store/repo"
  export GIT_WORK_TREE="$(_rv_project_dir)"
  export REVIEW_SLUG="$slug"
  export REVIEW_STORE="$store"
}

_rv_state_read() {
  local store="$1" key="$2"
  grep "^${key}=" "$store/state" 2>/dev/null | cut -d= -f2- || true
}

_rv_state_write() {
  local store="$1" key="$2" value="$3"
  local f="$store/state"
  mkdir -p "$store"
  if [[ -f "$f" ]] && grep -q "^${key}=" "$f"; then
    sed -i '' "s|^${key}=.*|${key}=${value}|" "$f"
  else
    echo "${key}=${value}" >> "$f"
  fi
}

# Run git against a specific store without touching the caller's env.
_rv_git() {
  local store="$1"; shift
  git --git-dir="$store/repo" --work-tree="$(_rv_project_dir)" "$@"
}

_rv_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Resolve a base ref for `review-start`: explicit arg, else merge-base with main/master.
_rv_default_base() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    git rev-parse "$explicit" 2>/dev/null && return 0
    echo "review-lib: cannot resolve base ref '$explicit'" >&2
    return 1
  fi
  for branch in main master; do
    if git rev-parse --verify "$branch" >/dev/null 2>&1; then
      git merge-base HEAD "$branch"
      return 0
    fi
  done
  echo "review-lib: no main or master branch found; pass an explicit base ref" >&2
  return 1
}
