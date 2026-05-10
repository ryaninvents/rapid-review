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

# Resolve the work-tree path for a store. Local-mode stores use their
# own snapshot dir; remote-mode stores use the project directory.
_rv_work_tree() {
  local store="$1"
  local mode
  mode=$(_rv_state_read "$store" "MODE")
  if [[ "$mode" == "local" ]]; then
    echo "$store/snapshot"
  else
    # Remote mode (or pre-MODE-field stores) use the project dir.
    local p
    p=$(_rv_state_read "$store" "PROJECT_DIR")
    [[ -n "$p" ]] && echo "$p" || echo "$(_rv_project_dir)"
  fi
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
  export GIT_WORK_TREE="$(_rv_work_tree "$store")"
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
  git --git-dir="$store/repo" --work-tree="$(_rv_work_tree "$store")" "$@"
}

_rv_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# Capture a snapshot of the project's working tree (incl. untracked,
# excl. gitignored) as a git tree object. Returns the tree SHA on stdout.
# Uses a temporary index so the project's real index isn't disturbed.
#
# Args:
#   $1 = absolute path to the project (must be inside its real git repo)
_rv_capture_snapshot() {
  local project="$1"
  local tmpidx
  tmpidx=$(mktemp -t rv-snap-idx.XXXXXX)
  # mktemp creates an empty file, but git wants either no file or a valid
  # index. Remove it so git creates a fresh index when it first writes.
  rm -f "$tmpidx"
  # cd into the project so git auto-detects its real .git/ — avoids `git -C`.
  (
    cd "$project"
    GIT_INDEX_FILE="$tmpidx" git add -A 2>/dev/null
    GIT_INDEX_FILE="$tmpidx" git write-tree
  )
  local rc=$?
  rm -f "$tmpidx"
  return $rc
}

# Materialize a snapshot tree into a store's snapshot/ work-dir. Wipes
# the existing snapshot dir contents first to handle file deletions.
# DOES NOT modify the review store's index ($store/repo/index).
#
# Args:
#   $1 = store dir (e.g. ~/.review/<hash>/<slug>)
#   $2 = tree SHA
_rv_materialize_snapshot() {
  local store="$1" tree="$2"
  local snap="$store/snapshot"

  rm -rf "$snap"
  mkdir -p "$snap"

  # Use a temp index so the review store's real index (HEAD/baseline) isn't
  # touched. We just need a scratch index to read-tree + checkout-index from.
  local tmpidx
  tmpidx=$(mktemp -t rv-mat-idx.XXXXXX)
  rm -f "$tmpidx"  # empty index file confuses git; let it create on demand
  GIT_INDEX_FILE="$tmpidx" git --git-dir="$store/repo" \
    read-tree "$tree"
  GIT_INDEX_FILE="$tmpidx" git --git-dir="$store/repo" --work-tree="$snap" \
    checkout-index --all --force
  rm -f "$tmpidx"
}

# After (re-)materializing the snapshot, mark untracked files as
# intent-to-add so they appear in `git diff` output. Operates on the review
# store's real index — i.e., adds new files since baseline.
#
# Args:
#   $1 = store dir
_rv_intent_to_add_untracked() {
  local store="$1"
  while IFS= read -r -d '' f; do
    git --git-dir="$store/repo" --work-tree="$store/snapshot" \
        add --intent-to-add -- "$f" 2>/dev/null || true
  done < <(git --git-dir="$store/repo" --work-tree="$store/snapshot" \
             ls-files --others --exclude-standard -z 2>/dev/null)
}

# Resolve a base ref for `review-start`: explicit arg, else merge-base with main/master.
# Always returns the merge-base of HEAD with the resolved ref, so that only the
# changes introduced by the current branch are shown (not accumulated upstream commits).
_rv_default_base() {
  local explicit="${1:-}"
  local ref
  if [[ -n "$explicit" ]]; then
    if ! ref=$(git rev-parse "$explicit" 2>/dev/null); then
      echo "review-lib: cannot resolve base ref '$explicit'" >&2
      return 1
    fi
  else
    ref=""
    for branch in main master; do
      if git rev-parse --verify "$branch" >/dev/null 2>&1; then
        ref=$(git rev-parse "$branch")
        break
      fi
    done
    if [[ -z "$ref" ]]; then
      echo "review-lib: no main or master branch found; pass an explicit base ref" >&2
      return 1
    fi
  fi
  git merge-base HEAD "$ref"
}

# Resolve a base ref for `review-start --local`: explicit arg, else HEAD.
# Unlike _rv_default_base, doesn't apply merge-base — we want the ref directly.
_rv_default_local_base() {
  local explicit="${1:-}"
  if [[ -n "$explicit" ]]; then
    git rev-parse "$explicit" 2>/dev/null && return 0
    echo "review-lib: cannot resolve base ref '$explicit'" >&2
    return 1
  fi
  git rev-parse HEAD
}
