#!/usr/bin/env bash
# Initialize a PR review store for the current project.
#
# Usage:
#   review-start <pr-slug> [<base-ref>]
#
# Creates ~/.review/<project-hash>/<pr-slug>/ with a git store whose HEAD
# points at the merge-base tree, and whose alternates reference $PWD/.git/objects.

set -euo pipefail
_RV_SELF="${BASH_SOURCE[0]}"; while [ -L "$_RV_SELF" ]; do _RV_SELF="$(readlink "$_RV_SELF")"; done; source "$(cd "$(dirname "$_RV_SELF")" && pwd)/review-lib.sh"

if [[ $# -lt 1 ]]; then
  echo "Usage: review-start <pr-slug> [<base-ref>]" >&2
  exit 64
fi

raw_slug="$1"
base_ref="${2:-}"

slug="$(_rv_sanitize_slug "$raw_slug")"
if [[ -z "$slug" ]]; then
  echo "review-start: slug must contain at least one alphanumeric character" >&2
  exit 64
fi

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "review-start: $PWD is not inside a git repo" >&2
  exit 1
fi

real_git_dir=$(git rev-parse --absolute-git-dir)
project_dir="$(_rv_project_dir)"
store="$(_rv_store_dir "$slug")"

if [[ -d "$store/repo" ]]; then
  echo "review-start: store already exists at $store" >&2
  echo "  use 'review-end $slug' to remove it first" >&2
  exit 1
fi

base_sha=$(_rv_default_base "$base_ref")
head_sha=$(git rev-parse HEAD)
head_ref=$(git symbolic-ref --short HEAD 2>/dev/null || echo "(detached)")

mkdir -p "$store/repo"
git --git-dir="$store/repo" init --quiet
git --git-dir="$store/repo" config core.bare false
git --git-dir="$store/repo" config user.name  "${REVIEW_USER_NAME:-PR Reviewer}"
git --git-dir="$store/repo" config user.email "${REVIEW_USER_EMAIL:-reviewer@local}"

# Alternates: reference the real repo's object store. No copying.
mkdir -p "$store/repo/objects/info"
echo "$real_git_dir/objects" > "$store/repo/objects/info/alternates"

# Set HEAD to a commit whose tree is the merge base — without disturbing the working tree.
tree_sha=$(git rev-parse "$base_sha^{tree}")
commit_sha=$(GIT_AUTHOR_NAME="PR Reviewer" GIT_AUTHOR_EMAIL="reviewer@local" \
             GIT_COMMITTER_NAME="PR Reviewer" GIT_COMMITTER_EMAIL="reviewer@local" \
             git --git-dir="$store/repo" commit-tree "$tree_sha" -m "base: ${base_sha:0:8}")
git --git-dir="$store/repo" update-ref HEAD "$commit_sha"

# Populate the index from HEAD so `git diff HEAD` semantics work cleanly.
git --git-dir="$store/repo" --work-tree="$project_dir" read-tree HEAD

# Mark untracked files as intent-to-add so they appear in `git diff HEAD`
# (otherwise new files in the PR are invisible to diff). Honors .gitignore.
while IFS= read -r -d '' f; do
  git --git-dir="$store/repo" --work-tree="$project_dir" add --intent-to-add -- "$f"
done < <(git --git-dir="$store/repo" --work-tree="$project_dir" \
           ls-files --others --exclude-standard -z)

_rv_state_write "$store" "PR_REF" "$head_ref"
_rv_state_write "$store" "BASE_SHA" "$base_sha"
_rv_state_write "$store" "REVIEW_BASE_COMMIT" "$commit_sha"
_rv_state_write "$store" "STARTED_AT" "$(_rv_now)"
_rv_state_write "$store" "LAST_REFRESHED_AT" "$(_rv_now)"
_rv_state_write "$store" "PROJECT_DIR" "$project_dir"

cat <<EOF
Review store created.

  Slug:    $slug
  Project: $project_dir
  Base:    ${base_sha:0:8}  (${base_ref:-merge-base})
  HEAD:    ${head_sha:0:8}  ($head_ref)
  Store:   $store

Activate with:
  review-shell $slug

Or set in your current shell:
  export GIT_DIR=$store/repo
  export GIT_WORK_TREE=$project_dir
EOF
