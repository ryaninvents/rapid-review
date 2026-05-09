# PR Chunk Review Workflow

Review large PRs incrementally in your terminal: stage chunks you've already
read, see new commits to the PR re-expose any reviewed code that someone
amended. Built on `git --git-dir` — your real `.git/` is never touched.

See `docs/review-workflow.md` for the full reference and quickstart.

## Layout

```
scripts/
  review-lib.sh         # shared helpers (sourced by the others)
  review-start.sh       # init a review store
  review-shell.sh       # subshell with GIT_DIR / GIT_WORK_TREE exported
  review-status.sh      # progress summary
  review-list.sh        # list active stores for $PWD
  review-end.sh         # delete a store
  review-refresh.sh     # git fetch + pull, show new outstanding diff
  review-remaining.sh   # diff of remaining unreviewed code
  nvim-review.sh        # launch nvim with sidebar open + explorer closed

nvim/
  lua/review/
    init.lua            # plugin entry, <leader>r* keymaps, statusline helper
    sidebar.lua         # the unreviewed-files sidebar
  plugin/review.lua     # auto-loader, registers commands when in a review-shell

docs/review-workflow.md
```

## Install on a new machine

```bash
# 1. Clone or copy this repo
git clone <this-repo>.git ~/.local/share/review-workflow
cd ~/.local/share/review-workflow

# 2. Symlink scripts onto $PATH (~/.local/bin must be on PATH; create if needed)
mkdir -p ~/.local/bin
for s in scripts/review-*.sh scripts/nvim-review.sh; do
  base=$(basename "$s" .sh)
  ln -sfn "$PWD/$s" "$HOME/.local/bin/$base"
done
chmod +x scripts/*.sh

# 3. Install the nvim plugin (mirrors the layout into your nvim config dir)
mkdir -p ~/.config/nvim/lua/review ~/.config/nvim/plugin
ln -sfn "$PWD/nvim/lua/review/init.lua"    ~/.config/nvim/lua/review/init.lua
ln -sfn "$PWD/nvim/lua/review/sidebar.lua" ~/.config/nvim/lua/review/sidebar.lua
ln -sfn "$PWD/nvim/plugin/review.lua"      ~/.config/nvim/plugin/review.lua

# 4. (Optional) drop the docs into your reference location
ln -sfn "$PWD/docs/review-workflow.md" ~/.claude/docs/review-workflow.md  # if applicable
```

The plugin auto-detects whether nvim was launched from inside a `review-shell`
(via `$GIT_DIR`); outside one, it's a no-op.

## Requirements

- `git` 2.0+
- `nvim` 0.8+ (winbar)
- `gitsigns.nvim` (recommended — used by `<leader>rh`/`rl`/`rf` for hunk staging)
- `lazygit` (optional — works inside the review shell when launched via env)

## Quickstart

```bash
git checkout pr-branch
review-start pr-123
review-shell pr-123
nvim-review

# In nvim: `<leader>rd` toggles the sidebar (already open via nvim-review).
# `s` stages the file under cursor; `V`-select then `s` stages multiple.
# `o` opens a colored diff. `c` commits a batch.
```
