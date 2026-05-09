# rapid-review

Review large PRs incrementally in your terminal: stage chunks you've already
read, see new commits to the PR re-expose any reviewed code that someone
amended. Built on `git --git-dir` — your real `.git/` is never touched.

See [`docs/review-workflow.md`](docs/review-workflow.md) for the full reference and quickstart.

---

## Install

Two halves — install whichever you need.

### Neovim plugin (lazy.nvim / LazyVim)

Drop a spec into your config (e.g. `~/.config/nvim/lua/plugins/rapid-review.lua`):

```lua
return {
  { "ryaninvents/rapid-review" },
}
```

That's it. The plugin auto-detects whether nvim was launched from inside a
`review-shell` (via `$GIT_DIR`); outside one, it's a complete no-op — no
commands, no keymaps, no `runtimepath` pollution.

If you'd rather not get the default `<leader>r*` keymaps:
```lua
return {
  {
    "ryaninvents/rapid-review",
    init = function() vim.g.review_no_default_mappings = 1 end,
  },
}
```

### Shell scripts (Antigen)

Add to your `.zshrc`:

```zsh
antigen bundle ryaninvents/rapid-review
```

That puts `review-start`, `review-shell`, `nvim-review`, and friends on
`$PATH`. Reload your shell or `antigen apply`.

### Shell scripts (Oh My Zsh)

```zsh
git clone https://github.com/ryaninvents/rapid-review.git \
  ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/rapid-review
# then add `rapid-review` to plugins=(...) in ~/.zshrc
```

Oh My Zsh sources `<plugin>/<plugin>.plugin.zsh`, which we ship at the repo
root.

### Manual install (no plugin manager)

```bash
git clone https://github.com/ryaninvents/rapid-review.git ~/.local/share/rapid-review

# Put scripts on PATH (~/.local/bin must already be on PATH)
mkdir -p ~/.local/bin
for s in ~/.local/share/rapid-review/scripts/*.sh; do
  base=$(basename "$s" .sh)
  ln -sfn "$s" "$HOME/.local/bin/$base"
done

# Wire up the nvim plugin
mkdir -p ~/.config/nvim/lua ~/.config/nvim/plugin
ln -sfn ~/.local/share/rapid-review/lua/review    ~/.config/nvim/lua/review
ln -sfn ~/.local/share/rapid-review/plugin/review.lua ~/.config/nvim/plugin/review.lua
```

---

## Layout

```
lua/review/                 # neovim plugin lua modules
  init.lua
  sidebar.lua
plugin/review.lua           # auto-loader (registers commands when in a review-shell)
rapid-review.plugin.zsh     # antigen / oh-my-zsh entry point
scripts/
  review-lib.sh             # shared helpers (sourced by the others)
  review-start.sh           # init a review store
  review-shell.sh           # subshell with GIT_DIR / GIT_WORK_TREE exported
  review-status.sh          # progress summary
  review-list.sh            # list active stores for $PWD
  review-end.sh             # delete a store
  review-refresh.sh         # git fetch + pull, show new outstanding diff
  review-remaining.sh       # diff of remaining unreviewed code
  nvim-review.sh            # launch nvim with sidebar open + explorer closed
docs/review-workflow.md     # full reference
```

## Requirements

- `git` 2.0+
- `nvim` 0.8+ (for `winbar` support)
- `gitsigns.nvim` (recommended — used by `<leader>rh` / `rl` / `rf` for hunk staging)
- `lazygit` (optional — works inside the review shell when launched via env)

## Quickstart

```bash
git checkout pr-branch
review-start pr-123
review-shell pr-123
nvim-review

# In nvim: <leader>rd toggles the sidebar (already open via nvim-review).
# `s` stages the file under cursor; V-select then `s` stages multiple.
# `o` opens a colored diff. `c` commits a batch.
```

See [`docs/review-workflow.md`](docs/review-workflow.md) for the full reference.

## License

MIT (or whatever you'd like — update this section before publishing widely).
