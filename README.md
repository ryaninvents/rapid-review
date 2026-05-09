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
  review-start              # init a review store
  review-shell              # subshell with GIT_DIR / GIT_WORK_TREE exported
  nvim-review               # launch nvim with sidebar open + explorer closed
  review-status             # progress summary
  review-list               # list active stores for $PWD
  review-end                # delete a store
  review-refresh            # git fetch + pull, show new outstanding diff
  review-remaining          # diff of remaining unreviewed code
  review-help               # cheatsheet (or --full to open the doc)
docs/review-workflow.md     # full reference
```

## Requirements

- `git` 2.0+
- `nvim` 0.8+ (for `winbar` support)
- `gitsigns.nvim` (recommended — used by `<leader>rh` / `rl` for hunk staging,
  and the sidebar auto-refreshes on its `User GitSignsUpdate` events)
- `lazygit` (optional — works inside the review shell when launched via env)

## Quickstart

```bash
git checkout pr-branch
review-start pr-123
review-shell pr-123
nvim-review

# In nvim: <leader>rr toggles the sidebar (already open via nvim-review).
# `s` toggles staged for the file under cursor; V-select then `s` toggles
# the whole group. `o` opens a colored diff. `c` commits a batch.
```

## Keymaps

### Inside the sidebar (buffer-local)

| Key | Action |
|---|---|
| `j` / `k` | navigate |
| `l` (or `<CR>`, double-click) | open file in adjacent window |
| `o` | open colored diff in adjacent window (`q` closes) |
| `s` | toggle staged for the file under cursor |
| `V`-select rows then `s` | toggle staged for the selection (stages all if any unstaged; else unstages all) |
| `c` | prompt for commit message and commit staged files |
| `r` | refresh sidebar |
| `q` | close sidebar |

### Global `<leader>r*` (active in a review-shell)

`<leader>` is `<Space>` in LazyVim by default. Marked **(sidebar-aware)** keys
work both from a file buffer *and* from inside the sidebar.

| Keys | Action |
|---|---|
| `<leader>rr` | toggle sidebar |
| `<leader>rd` | open colored diff view **(sidebar-aware)** |
| `<leader>rf` | toggle staged file **(sidebar-aware)** |
| `<leader>rh` | stage current hunk (gitsigns; file buffer only) |
| `<leader>rl` | stage visual line range (gitsigns; file buffer only) |
| `<leader>rc` | commit reviewed batch (prompts) |
| `<leader>rs` | status floating window |
| `<leader>ru` | refresh sidebar |
| `<leader>rZ` | undo last batch — `git reset --soft HEAD~1` (prompts) |
| `<leader>rn` | jump to next unreviewed file |

The sidebar buffer-local keymaps deliberately **don't bind `<Space>`**, so
`<leader>r*` mappings keep firing with the cursor inside the sidebar.

`<leader>rh` and `<leader>rl` are hidden from which-key menus when the cursor
is in the sidebar or diff view (gitsigns isn't attached there).

The sidebar auto-refreshes on:
- gitsigns `User GitSignsUpdate` / `GitSignsChanged` events
- after every `<leader>r*` operation that affects status
- after `BufWritePost` in any buffer
- in response to its own `s` / `c` actions

External staging (lazygit in another terminal, plain `git add`, etc.) still
needs a manual `r` in the sidebar — there's no filesystem watcher.

See [`docs/review-workflow.md`](docs/review-workflow.md) for the full reference.

## License

[MIT](LICENSE) © Ryan Kennedy
