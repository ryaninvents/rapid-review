-- review.nvim — unreviewed-files sidebar.
--
-- Built directly on git shellouts with explicit --git-dir/--work-tree flags
-- (taken from $GIT_DIR / $GIT_WORK_TREE). No plugin dependencies.

local M = {}

local ns = vim.api.nvim_create_namespace("review_sidebar")

-- Explicit gray for reviewed rows. `default = true` lets users/themes override
-- by defining `ReviewSidebarDimmed` themselves. Re-applied on ColorScheme so
-- theme switches don't clobber it.
local function setup_highlights()
  vim.api.nvim_set_hl(0, "ReviewSidebarDimmed", {
    fg = "#808080",
    ctermfg = 244,
    default = true,
  })
end

setup_highlights()
vim.api.nvim_create_autocmd("ColorScheme", {
  group = vim.api.nvim_create_augroup("ReviewSidebarHL", { clear = true }),
  callback = setup_highlights,
})

local state = {
  buf = nil,           -- sidebar buffer handle
  win = nil,           -- sidebar window handle
  target_win = nil,    -- where `l` opens files
  files = {},          -- ordered list of file entries
}

-- ---------- helpers ----------

local function git_dir()    return vim.env.GIT_DIR end
local function work_tree()  return vim.env.GIT_WORK_TREE end

local function in_review_shell()
  local gd = git_dir()
  return gd and gd:match("/%.review/") ~= nil
end

local function git(args)
  local cmd = { "git", "--git-dir=" .. git_dir(), "--work-tree=" .. work_tree() }
  for _, a in ipairs(args) do table.insert(cmd, a) end
  local out = vim.fn.systemlist(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("review: git failed: " .. table.concat(out, "\n"), vim.log.levels.ERROR)
    return {}
  end
  return out
end

local function parse_numstat(lines)
  local out = {}
  for _, line in ipairs(lines) do
    local add, del, path = line:match("^(%S+)%s+(%S+)%s+(.+)$")
    if path then
      out[path] = { add = tonumber(add) or 0, del = tonumber(del) or 0 }
    end
  end
  return out
end

-- Parse `git status --porcelain=v1 -uall` line by line.
-- `-uall` enumerates every untracked file individually, instead of collapsing
-- an entire untracked directory to a single "?? dir/" entry.
-- Returns map: path → 2-char status string ("XY"). XY is index/worktree per git.
local function parse_status()
  local out = {}
  for _, line in ipairs(git({ "status", "--porcelain=v1", "-uall" })) do
    if #line >= 4 then
      local code = line:sub(1, 2)
      local rest = line:sub(4)
      -- Rename/copy form: "<dest> -> <orig>". We track the destination path.
      local arrow = rest:find(" %-> ")
      local path = arrow and rest:sub(1, arrow - 1) or rest
      if path ~= "" and code ~= "" then
        out[path] = code
      end
    end
  end
  return out
end

local function load_files()
  -- numstat for line counts, status for state + signifier.
  local unstaged  = parse_numstat(git({ "diff", "--numstat" }))
  local staged_raw = parse_numstat(git({ "diff", "--cached", "--numstat" }))
  local status   = parse_status()

  local seen = {}
  for p, _ in pairs(status)   do seen[p] = true end
  for p, _ in pairs(unstaged) do seen[p] = true end
  for p, _ in pairs(staged_raw) do seen[p] = true end

  local list = {}
  for path, _ in pairs(seen) do
    local code = status[path] or "  "
    local idx_col = code:sub(1, 1)  -- staged column
    local wt_col  = code:sub(2, 2)  -- working-tree column

    local has_staged   = idx_col ~= " " and idx_col ~= "?"
    local has_unstaged = wt_col  ~= " "

    -- Intent-to-add markers (committed by review-start) appear as "AM" or "A "
    -- with zero numstat entries. The state derivation handles this naturally:
    -- "AM" → has_staged + has_unstaged → partial (correct: index is empty,
    --        working has content). For our review semantics, intent-to-add by
    --        itself ("A ") with no numstat means nothing to display, but we
    --        keep it visible so the user can see new-file presence.
    local kind
    if      has_unstaged and has_staged then kind = "partial"
    elseif  has_unstaged then                kind = "unreviewed"
    elseif  has_staged   then                kind = "reviewed"
    else                                     kind = "unreviewed"  -- "??" untracked
    end

    local u, s = unstaged[path], staged_raw[path]
    local add = (u and u.add or 0) + (s and s.add or 0)
    local del = (u and u.del or 0) + (s and s.del or 0)

    table.insert(list, {
      path = path, add = add, del = del, state = kind,
      status = code,
      has_unstaged = has_unstaged, has_staged = has_staged,
    })
  end
  table.sort(list, function(a, b) return a.path < b.path end)
  return list
end

-- Returns done, total, pct. Total is the sum of added + deleted lines across
-- all files in the diff; done counts the same for fully-reviewed files.
local function progress_stats(files)
  local total, done = 0, 0
  for _, f in ipairs(files) do
    total = total + f.add + f.del
    if f.state == "reviewed" then
      done = done + f.add + f.del
    end
  end
  local pct = total == 0 and 0 or math.floor(done * 100 / total)
  return done, total, pct
end

-- ---------- rendering ----------

-- Each row is "<XY> <path>  +ADD -DEL".
--   XY     = 2-char git porcelain status (e.g. " M", "M ", "MM", "A ", "??")
--   path   = takes the remainder of the sidebar width
--   COUNTER cell is fixed at ~14 cols ("+99999 -99999").
local COUNTER_WIDTH = 14
local STATUS_WIDTH  = 3   -- "XY" + 1 space

local function path_width()
  local total
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    total = vim.api.nvim_win_get_width(state.win)
  else
    total = vim.g.review_sidebar_width or 40
  end
  local w = total - STATUS_WIDTH - COUNTER_WIDTH - 2
  if w < 12 then w = 12 end
  return w
end

local function format_line(f)
  local pw = path_width()
  local path = f.path
  if #path > pw then
    path = "…" .. path:sub(-pw + 1)
  end
  -- Status code displayed as-is; spaces inside it carry meaning per `git status`.
  return string.format("%-2s %-" .. pw .. "s  +%-5d -%-5d",
    f.status or "  ", path, f.add, f.del)
end

local function render(buf, files)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)

  if #files == 0 then
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
      "  no remaining changes",
      "",
      "  review complete!",
    })
    vim.bo[buf].modifiable = false
    return
  end

  local lines = {}
  for _, f in ipairs(files) do
    table.insert(lines, format_line(f))
  end
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  local pw = path_width()
  for i, f in ipairs(files) do
    local row = i - 1

    if f.state == "reviewed" then
      -- Dim the whole row (status + path + counters) so reviewed files recede.
      vim.api.nvim_buf_add_highlight(buf, ns, "ReviewSidebarDimmed", row, 0, -1)
    elseif f.state == "partial" then
      -- Highlight just the path segment; status cell + counters stay neutral.
      vim.api.nvim_buf_add_highlight(buf, ns, "DiagnosticInfo", row,
        STATUS_WIDTH, STATUS_WIDTH + pw)
    end
    -- Counter cell uses default text color regardless of state.
  end
end

local function update_winbar()
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
  local slug = vim.env.REVIEW_SLUG or "?"
  local done, total, pct = progress_stats(state.files)
  -- Winbar inherits statusline format rules; avoid `[ ]` (format specifiers)
  -- and double `%%` for a literal percent sign.
  vim.wo[state.win].winbar = string.format(
    " review:%s  %d%%%%  (%d/%d SLOC)", slug, pct, done, total)
end

-- ---------- actions ----------

local function file_at_cursor()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return nil end
  if not state.win or not vim.api.nvim_win_is_valid(state.win) then return nil end
  local row = vim.api.nvim_win_get_cursor(state.win)[1]
  return state.files[row]
end

function M.refresh()
  if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
  state.files = load_files()
  render(state.buf, state.files)
  update_winbar()
end

local function ensure_target_win()
  local target = state.target_win
  if not target or not vim.api.nvim_win_is_valid(target) or target == state.win then
    vim.cmd("rightbelow vsplit")
    target = vim.api.nvim_get_current_win()
    state.target_win = target
  else
    vim.api.nvim_set_current_win(target)
  end
  return target
end

function M.open_file()
  local f = file_at_cursor()
  if not f then return end
  ensure_target_win()
  vim.cmd("edit " .. vim.fn.fnameescape(f.path))
end

-- Open a colored diff for the given path. Tier-fallback: unreviewed → staged
-- → full review-relative. If `target_win` is given (and valid), the diff
-- replaces that window's buffer; otherwise a `rightbelow vsplit` is created.
function M.open_diff_for(path, target_win)
  if not path or path == "" then return end

  local lines = git({ "diff", "--", path })
  local label = "unreviewed"
  if #lines == 0 then
    lines = git({ "diff", "--cached", "--", path })
    label = "staged"
  end
  if #lines == 0 then
    lines = git({ "diff", "HEAD", "--", path })
    label = "all"
  end
  if #lines == 0 then
    vim.notify("review: no diff for " .. path, vim.log.levels.INFO)
    return
  end

  if not target_win or not vim.api.nvim_win_is_valid(target_win) then
    vim.cmd("rightbelow vsplit")
    target_win = vim.api.nvim_get_current_win()
  end

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile  = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype  = "diff"
  vim.api.nvim_buf_set_name(buf, "review-diff://" .. label .. "/" .. path)
  vim.api.nvim_win_set_buf(target_win, buf)
  -- Mark with a buffer-scoped flag so <leader>rh / <leader>rd / etc. can
  -- detect we're in a review-managed diff buffer (filetype stays "diff" so
  -- vim's built-in diff syntax highlighting still applies).
  vim.b[buf].review_diff = true
  vim.keymap.set("n", "q", "<cmd>close<cr>",
    { buffer = buf, silent = true, desc = "close diff" })

  -- Hide leader maps that don't apply in a diff view (gitsigns isn't attached
  -- here). Hunk-level / line-level staging from inside the diff buffer is
  -- tracked at https://github.com/ryaninvents/rapid-review/issues/1 — until
  -- it lands, the diff view is read-only.
  local hide = function(mode, lhs)
    vim.keymap.set(mode, lhs, function() end,
      { buffer = buf, silent = true, desc = "which_key_ignore" })
  end
  hide("n", "<leader>rh")
  hide("v", "<leader>rl")
end

-- Sidebar `o` keymap: open diff for file under cursor, into the target window.
function M.open_diff()
  local f = file_at_cursor()
  if not f then return end
  ensure_target_win()
  M.open_diff_for(f.path, state.target_win)
end

function M.toggle_stage()
  local f = file_at_cursor()
  if not f then return end
  if f.has_staged and not f.has_unstaged then
    git({ "reset", "HEAD", "--", f.path })
  else
    git({ "add", "--", f.path })
  end
  M.refresh()
end

-- Stage every file in the current visual line range.
-- Multi-select doesn't toggle (the semantics are ambiguous when the selection
-- mixes states); it always stages. Unstage individual rows in normal mode.
function M.stage_visual()
  -- Use the V-mark range. After leaving visual mode, '< and '> hold the bounds.
  -- We're called while still in visual mode via <Esc> first to commit the marks.
  local mode = vim.fn.mode()
  if mode == "V" or mode == "v" or mode == "" then
    -- "Esc" out so the marks update.
    vim.cmd('execute "normal! \\<Esc>"')
  end
  local s = vim.fn.line("'<")
  local e = vim.fn.line("'>")
  if s == 0 or e == 0 then return end
  if s > e then s, e = e, s end

  local touched = 0
  for row = s, e do
    local f = state.files[row]
    if f and f.has_unstaged then
      git({ "add", "--", f.path })
      touched = touched + 1
    end
  end
  if touched > 0 then
    vim.notify(string.format("review: staged %d file%s",
      touched, touched == 1 and "" or "s"))
  end
  M.refresh()
end

function M.commit()
  vim.ui.input({ prompt = "Commit reviewed: ", default = "reviewed: " }, function(msg)
    if not msg then return end
    msg = vim.trim(msg)
    if msg == "" or msg == "reviewed:" then
      vim.notify("review: empty message — commit aborted", vim.log.levels.WARN)
      return
    end
    local out = git({ "commit", "-m", msg })
    if vim.v.shell_error == 0 then
      vim.notify("review: " .. (out[#out] or "committed"), vim.log.levels.INFO)
    end
    M.refresh()
  end)
end

function M.close()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_win_close(state.win, true)
  end
  state.win = nil
  state.buf = nil
end

function M.open()
  if not in_review_shell() then
    vim.notify(
      "review.sidebar: GIT_DIR does not point at a review store.\n" ..
      "Launch nvim from inside `review-shell <slug>`.",
      vim.log.levels.ERROR)
    return
  end

  if state.win and vim.api.nvim_win_is_valid(state.win) then
    vim.api.nvim_set_current_win(state.win)
    return
  end

  state.target_win = vim.api.nvim_get_current_win()

  local width = vim.g.review_sidebar_width or 40

  -- Open at the far left (topleft anchor) and pin its width with winfixwidth so
  -- subsequent splits don't reflow it. Explicitly set width after creation
  -- because :topleft Nvsplit's column hint is advisory under equalalways.
  vim.cmd("topleft " .. width .. "vsplit")
  state.win = vim.api.nvim_get_current_win()
  state.buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_win_set_buf(state.win, state.buf)
  vim.api.nvim_win_set_width(state.win, width)

  local buf = state.buf
  local win = state.win
  vim.bo[buf].buftype   = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile  = false
  vim.bo[buf].filetype  = "review-sidebar"
  vim.api.nvim_buf_set_name(buf, "review://" .. (vim.env.REVIEW_SLUG or "?"))
  vim.wo[win].number         = false
  vim.wo[win].relativenumber = false
  vim.wo[win].wrap           = false
  vim.wo[win].cursorline     = true
  vim.wo[win].signcolumn     = "no"
  vim.wo[win].winfixwidth    = true   -- pin width across other split changes
  vim.wo[win].list           = false
  vim.wo[win].foldcolumn     = "0"

  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { buffer = buf, silent = true, nowait = true, desc = desc })
  end
  -- We deliberately do NOT bind `<Space>` here — that's the leader key in
  -- LazyVim/most configs, and shadowing it would block `<leader>r*` mappings
  -- (sidebar toggle, commit, status, etc.) from firing inside the sidebar.
  map("n", "l",              M.open_file,    "review: open file")
  map("n", "o",              M.open_diff,    "review: open colored diff")
  map("n", "s",              M.toggle_stage, "review: toggle stage")
  map("x", "s",              M.stage_visual, "review: stage selected files")
  map("n", "c",              M.commit,       "review: commit reviewed batch")
  map("n", "r",              M.refresh,      "review: refresh")
  map("n", "q",              M.close,        "review: close sidebar")
  map("n", "<CR>",           M.open_file,    "review: open file")
  -- Double-click also opens the file. Single-click just moves the cursor (vim default).
  map("n", "<2-LeftMouse>",  M.open_file,    "review: open file (double-click)")

  -- Hide leader maps that don't apply here from the which-key menu by
  -- shadowing them with which_key_ignore-tagged buffer-local no-ops.
  -- The hunk- and line-stage operations only make sense in a file buffer.
  local hide = function(mode, lhs)
    vim.keymap.set(mode, lhs, function() end,
      { buffer = buf, silent = true, desc = "which_key_ignore" })
  end
  hide("n", "<leader>rh")
  hide("v", "<leader>rl")

  -- Auto-refresh after writes in the project, since they may change `git diff`.
  local group = vim.api.nvim_create_augroup("ReviewSidebar", { clear = true })
  vim.api.nvim_create_autocmd("BufWritePost", {
    group = group,
    callback = function()
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        vim.schedule(M.refresh)
      end
    end,
  })
  -- Reflow path column when the user drag-resizes the sidebar window.
  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = group,
    callback = function()
      if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then return end
      if not state.win or not vim.api.nvim_win_is_valid(state.win) then return end
      -- Only re-render layout (not re-fetch git data); cheap.
      vim.schedule(function()
        if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
          render(state.buf, state.files)
        end
      end)
    end,
  })
  -- Clean up state if the buffer is wiped out from under us.
  vim.api.nvim_create_autocmd("BufWipeout", {
    group = group,
    buffer = buf,
    callback = function()
      state.buf = nil
      state.win = nil
    end,
  })

  -- Auto-refresh when gitsigns reports updates. Covers any path that goes
  -- through gitsigns (hunk staging via :Gitsigns stage_hunk, <leader>rh,
  -- <leader>rl, <leader>rf in a file buffer, etc.).
  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = { "GitSignsUpdate", "GitSignsChanged" },
    callback = function()
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        vim.schedule(M.refresh)
      end
    end,
  })

  M.refresh()
end

function M.toggle()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    M.close()
  else
    M.open()
  end
end

return M
