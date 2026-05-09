# PR Chunk Review Workflow

Stage chunks of a large PR as you read them. The diff shrinks as you progress. New pushes to the PR re-expose any reviewed code that someone else changed.

The trick: a side `git` store (using `--git-dir`) whose HEAD is "what I've already reviewed." Your real `.git/` is never touched.

---

## TL;DR

```bash
git checkout pr-branch
review-start pr-123              # init the review store
review-shell pr-123              # subshell with GIT_DIR exported
nvim-review                      # nvim with sidebar open, file explorer closed
                                 # …read code, `s` on a row to stage…
                                 # …or :Gitsigns stage_hunk inside a buffer…
git commit -m "reviewed: auth"   # (or `c` in the sidebar; or <leader>rc)
review-status                    # progress
exit                             # leave the shell when done for now
review-end pr-123                # delete the store when fully reviewed
```

---

## Mental Model

> Review-store HEAD = "what I've already reviewed."
> `git diff` = "what's left."

- Each commit in the review store advances your reviewed pointer.
- The working tree is the PR head (set by your normal `git checkout`).
- `git diff HEAD` (inside the review shell) shows everything you haven't staged or committed yet.
- After `git pull`, any line that was in a commit you'd "reviewed" but was then changed reappears in the diff. That's the point — you re-read only the lines someone touched since.

---

## Lifecycle

### 1. Check out the PR

```bash
git fetch origin
git checkout pr-branch
```

Your normal git workflow. The review tooling sits beside it.

### 2. Initialize the review store

```bash
review-start pr-123              # base = merge-base(HEAD, main, fallback master)
review-start pr-123 origin/dev   # explicit base ref
```

Creates `~/.review/<project-hash>/pr-123/repo/`. The store uses git alternates pointing at your real `.git/objects`, so it can reference any commit/tree/blob without copying. HEAD in the review store is set to the merge base's tree without disturbing your working tree.

The slug (`pr-123`) is whatever you want; it's your label for this review.

### 3. Enter the review shell

```bash
review-shell pr-123
```

Your prompt now shows `(review:pr-123)`. Inside this shell:

- `GIT_DIR` and `GIT_WORK_TREE` point at the review store and your project, respectively.
- **Every git command** — `git status`, `git diff`, `git add`, `git commit` — operates on the review store.
- **Every nvim plugin that uses git** (gitsigns, fugitive, lazygit) does the same automatically.
- **`nvim-review`** (the recommended launcher) opens nvim with the sidebar already visible and any file explorer (neo-tree / nvim-tree) closed.
- The real repo is unaffected. `git log` outside the shell shows nothing new.

Omit the slug if there's only one store for the current project: `review-shell` picks it. With multiple stores, pass the slug explicitly.

### 4. Read and stage

Launch `nvim-review` (or plain `nvim` and open the sidebar with `<leader>rd`).
The sidebar lists every file in the diff with a porcelain status column on the
left and `+N -M` line counts on the right.

In the sidebar:

| Key | Action |
|---|---|
| `j` / `k` | move down / up |
| `l` (or `<CR>`) | open file in adjacent window |
| `o` | open colored diff in adjacent window |
| `<Space>` | toggle stage/unstage for the file under cursor |
| `V`-select rows then `<Space>` | stage every selected file in one go |
| `c` | prompt for commit message and commit staged files |
| `r` | refresh |
| `q` | close sidebar |

Inside a file buffer (hunk-level review):

| Action | Command |
|---|---|
| Stage current hunk | `:Gitsigns stage_hunk` |
| Stage selected lines (visual) | `:'<,'>Gitsigns stage_hunk` |
| Stage whole file | `:Gitsigns stage_buffer` |
| Unstage hunk | `:Gitsigns reset_hunk` |

Or use fugitive: `:G`, navigate to a hunk, press `s` to stage. Or lazygit.

Staging shrinks `git diff` immediately. You don't have to commit to make
progress; commits just give you a point to roll back to.

### 5. Commit a batch periodically

```bash
git commit -m "reviewed: routes + middleware"
```

Or, inside nvim, `<leader>rc` (with `review.nvim` enabled) prompts for a message.

### 6. Check progress

```bash
review-status
```

Shows files reviewed/partial/untouched and line-level percentages.

### 7. New commits land on the PR

In a separate terminal (or after `exit`-ing the review shell — `git pull` requires the real `GIT_DIR`):

```bash
git pull
```

Re-enter `review-shell pr-123`. Now `git diff HEAD` shows:

- Anything you hadn't yet reviewed
- **Plus** anything that *changed* in code you previously reviewed

The latter is the load-bearing feature. Lines that disappear from the diff are still reviewed; lines that reappear get a second pass.

### 8. Finish up

```bash
review-end pr-123
```

Confirms first if there's still unreviewed code. Deletes the store.

---

## Daily Commands

| Command | Purpose |
|---|---|
| `review-start <slug> [<base>]` | Init review store at the merge base |
| `review-shell [<slug>]` | Subshell with `GIT_DIR` set |
| `nvim-review [files…]` | Launch nvim with sidebar open + file explorer closed (run from inside `review-shell`) |
| `review-status [<slug>]` | Progress summary |
| `review-list` | All active stores for `$PWD` |
| `review-refresh [<slug>]` | `git fetch` + `git pull --ff-only` (run outside review-shell) |
| `review-remaining [<slug>] [-- <git-diff-args>]` | Diff of remaining unreviewed code |
| `review-end <slug> [--force]` | Delete the store |

---

## Sidebar (`review.nvim`)

`<leader>rd` toggles the unreviewed-files sidebar. The winbar shows progress as
percent + SLOC counts.

```
 review:pr-123  60%  (123/456 SLOC)
─────────────────────────────────────
 M src/auth/middleware.ts  +89  -12
 M src/auth/jwks.ts        +145  -0
MM src/types/jwt.ts        +45   -2
M  tests/auth.test.ts      +210 -50
A  docs/jwt-design.md      +120  -0
```

### Status column (left)

Two-char `git status --porcelain` code, identical to what `git status --short`
or lazygit shows. The first char is the index/staged column; the second is the
working-tree column.

| Code | Meaning |
|---|---|
| ` M` | Modified, **not staged** (unreviewed) |
| `M ` | Modified, **staged** (reviewed in this batch) |
| `MM` | Modified, **partially** staged (some hunks reviewed, some not) |
| `A ` | New file added in this PR, fully staged |
| `AM` | New file added, with further unstaged tweaks |
| `??` | Untracked (rare — `review-start` and `review-shell` mark new files as intent-to-add) |
| ` D` / `D ` | Deletion, unstaged / staged |

Same matrix as anywhere else in git tooling — your `lazygit` muscle memory transfers.

### Color coding

- **Default** — unreviewed
- **Cyan** (`DiagnosticInfo`) — partial (some hunks staged, some not)
- **Gray** (`ReviewSidebarDimmed`, `#808080` / `ctermfg=244`) — reviewed; entire row dimmed including the `+N -M` counters
- The `+N -M` counters are deliberately *not* color-coded green/red, to keep the row scannable

Override the dim color in your config:

```lua
vim.api.nvim_set_hl(0, "ReviewSidebarDimmed", { fg = "#666666", ctermfg = 240 })
```

### Sidebar keymaps (buffer-local)

| Key | Action |
|---|---|
| `j` / `k` | move down / up |
| `l` (or `<CR>`, or double-click) | open file in adjacent window |
| `o` | open colored diff in adjacent window (`q` closes the diff buffer) |
| `s` | toggle stage/unstage for the file under cursor |
| `V`-select then `s` | stage every selected file (visual mode) |
| `c` | prompt for commit message and commit staged files |
| `r` | refresh |
| `q` | close sidebar |

The sidebar refreshes automatically after `BufWritePost` and after any
stage/commit action it performs. **External** changes (e.g. staging via lazygit
or `git add` in another terminal) require a manual `r` to refresh.

Note: the buffer-local sidebar keymaps deliberately don't bind `<Space>` —
that's the leader key in LazyVim, so all `<leader>r*` mappings (toggle
sidebar, status, commit, undo, etc.) keep working with the cursor inside the
sidebar.

### Width

Default 40 columns, pinned with `winfixwidth` so it doesn't reflow when other
splits open or close. Drag-resize works — the path column reflows live to fill
whatever width you give it. Override the default:

```lua
vim.g.review_sidebar_width = 50  -- before opening (or change and reopen)
```

---

## Global `<leader>r*` Keymaps

Active automatically when nvim is launched from a review shell. Marked
**(sidebar-aware)** keymaps work both from a file buffer *and* from inside the
sidebar — they dispatch on context.

| Keys | Action |
|---|---|
| `<leader>rr` | Toggle sidebar |
| `<leader>rd` | Open colored diff view **(sidebar-aware)** — sidebar: file under cursor; file buffer: current file |
| `<leader>rf` | Stage file **(sidebar-aware)** — sidebar: file under cursor; file buffer: stage_buffer |
| `<leader>rh` | Stage current hunk (gitsigns; file buffer only) |
| `<leader>rl` | Stage visual line range (gitsigns, visual mode; file buffer only) |
| `<leader>rc` | Commit reviewed batch (prompts) |
| `<leader>rs` | Status floating window |
| `<leader>ru` | Refresh sidebar |
| `<leader>rZ` | Undo last batch (`git reset --soft HEAD~1`) — prompts before running |
| `<leader>rn` | Jump to next unreviewed file |

`<leader>rr`, `<leader>rd`, `<leader>rf`, `<leader>rc`, `<leader>rs`, `<leader>ru`, and `<leader>rZ` all fire correctly with the cursor inside the sidebar (the buffer-local keymaps deliberately don't bind `<Space>`, so the leader key passes through).

To disable the default keymaps: `vim.g.review_no_default_mappings = 1` in your nvim config. The plugin still exposes commands (`:Review*`).

---

## Tips

- **Whole-file fast path:** put cursor on a sidebar row, hit `s` — the entire file stages in one keystroke. Then `c` to commit a batch.
- **Multi-file fast path:** `V`-select several rows in the sidebar, hit `s` — every selected file stages at once.
- **Single-line staging:** inside a buffer, put cursor on a line, `V` to enter visual line mode, then `:Gitsigns stage_hunk`. Selected lines stage regardless of hunk boundaries.
- **Quick diff peek:** in the sidebar, `o` opens a syntax-highlighted diff buffer in the adjacent window. `q` closes it.
- **Multiple PRs in flight:** `review-list` shows all stores; `review-shell` with no arg auto-picks if exactly one exists.
- **Lines that re-appear after a pull:** those are exactly the ones someone changed since your previous review pass. Re-read only those.
- **Coming back to a session:** the store persists. Just `review-shell pr-123` again. State is durable until you `review-end`.
- **External staging (e.g. lazygit):** the sidebar doesn't auto-refresh on out-of-process changes; press `r` in the sidebar to pull in the latest state.
- **Where stores live:** `~/.review/<md5-of-cwd>/<slug>/`. Safe to inspect or delete manually if you ever want to.
- **Real repo is untouched:** outside the review shell, `git status`, `git log`, `git push` work exactly as they always did. Nothing about the review changes anything in `.git/`.

---

## When NOT to use this

- **Tiny PRs** (under ~50 lines): just review them in your normal git tool. The setup overhead isn't worth it.
- **Reviewing on GitHub's web UI**: this is for terminal/nvim review. If you live in the GitHub PR view, there's nothing here for you.
- **You want to leave PR comments**: this workflow is read-only; it doesn't post anything. Use `gh pr review` or the web UI for comments. Use this for the *reading* phase, then comment afterward.
