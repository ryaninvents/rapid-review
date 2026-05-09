#!/usr/bin/env bash
# Print a progress summary for a review store.
#
# Usage:
#   review-status [<pr-slug>]

set -euo pipefail
_RV_SELF="${BASH_SOURCE[0]}"; while [ -L "$_RV_SELF" ]; do _RV_SELF="$(readlink "$_RV_SELF")"; done; source "$(cd "$(dirname "$_RV_SELF")" && pwd)/review-lib.sh"

slug=$(_rv_resolve_slug "${1:-}")
store=$(_rv_store_dir "$slug")

base_sha=$(_rv_state_read "$store" "BASE_SHA")
pr_ref=$(_rv_state_read "$store" "PR_REF")
started_at=$(_rv_state_read "$store" "STARTED_AT")
refreshed_at=$(_rv_state_read "$store" "LAST_REFRESHED_AT")

# Files: count from numstat snapshots.
#   remaining = working tree vs index (unstaged = "still to review")
#   staged    = index vs HEAD (already-marked-reviewed in this batch)
#   committed = log of review commits since base
review_base=$(_rv_state_read "$store" "REVIEW_BASE_COMMIT")
remaining=$(_rv_git "$store" diff --numstat 2>/dev/null || true)
staged=$(_rv_git "$store" diff --cached --numstat 2>/dev/null \
          | awk 'NF >= 3 && ($1+$2) > 0' || true)
if [[ -n "$review_base" ]]; then
  committed=$(_rv_git "$store" log --numstat --pretty=format: "${review_base}..HEAD" 2>/dev/null | grep -v '^$' || true)
else
  committed=""
fi

count_lines() {
  # Sum +adds and -dels from a numstat blob (skipping binary entries marked with -).
  awk 'NF >= 3 && $1 ~ /^[0-9]+$/ {a+=$1; d+=$2} END {printf "%d %d", a+0, d+0}' <<<"$1"
}

read -r r_add r_del <<<"$(count_lines "$remaining")"
read -r s_add s_del <<<"$(count_lines "$staged")"
read -r c_add c_del <<<"$(count_lines "$committed")"

total_add=$((r_add + s_add + c_add))
total_del=$((r_del + s_del + c_del))
done_add=$((s_add + c_add))
done_del=$((s_del + c_del))

pct() {
  local done=$1 total=$2
  if [[ "$total" -eq 0 ]]; then echo "—"; return; fi
  printf "%d%%" $(( done * 100 / total ))
}

# Files breakdown
remaining_files=$(printf "%s\n" "$remaining" | awk 'NF{print $3}' | sort -u)
staged_files=$(printf "%s\n" "$staged" | awk 'NF{print $3}' | sort -u)
committed_files=$(printf "%s\n" "$committed" | awk 'NF{print $3}' | sort -u)

# A file is "reviewed" if it appears in committed or staged AND has no remaining lines.
# A file is "partial" if it appears in both staged/committed AND remaining.
# A file is "untouched" if it appears only in remaining.
total_files=$(printf "%s\n%s\n%s\n" "$remaining_files" "$staged_files" "$committed_files" | sort -u | grep -c .)
reviewed_files=$(comm -23 <(printf "%s\n" "$staged_files" "$committed_files" | sort -u | grep .) <(printf "%s\n" "$remaining_files" | grep .) | grep -c . || true)
untouched_files=$(comm -23 <(printf "%s\n" "$remaining_files" | grep .) <(printf "%s\n" "$staged_files" "$committed_files" | sort -u | grep .) | grep -c . || true)
partial_files=$(( total_files - reviewed_files - untouched_files ))
[[ "$partial_files" -lt 0 ]] && partial_files=0

cat <<EOF
PR: $slug  base: ${base_sha:0:8}  head: ${pr_ref:-?}
Started:   ${started_at:-?}
Refreshed: ${refreshed_at:-?}

Files:    $reviewed_files reviewed  /  $partial_files partial  /  $untouched_files untouched   ($total_files total)
Lines:  +$done_add / +$total_add reviewed  ($(pct "$done_add" "$total_add"))   −$done_del / −$total_del reviewed  ($(pct "$done_del" "$total_del"))
EOF

if [[ "$untouched_files" -gt 0 ]]; then
  echo
  echo "Untouched files:"
  comm -23 <(printf "%s\n" "$remaining_files" | grep . | sort) \
           <(printf "%s\n" "$staged_files" "$committed_files" | grep . | sort -u) \
    | while read -r f; do
        line=$(printf "%s\n" "$remaining" | awk -v f="$f" '$3==f {printf "+%s / -%s", $1, $2}')
        printf "  %-40s  %s\n" "$f" "$line"
      done
fi
