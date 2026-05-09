-- review.nvim — entry point.
--
-- Auto-detects review-shell via $GIT_DIR. When active, exposes a sidebar and
-- leader-prefixed keymaps that wrap gitsigns/fugitive against the review store.

local M = {}

local function in_review_shell()
  local gd = vim.env.GIT_DIR
  return gd and gd:match("/%.review/") ~= nil
end

M.is_active = in_review_shell

function M.sidebar()
  return require("review.sidebar")
end

-- Convenience wrappers around gitsigns; fall back to direct git if gitsigns
-- isn't loaded.
local function has_gitsigns()
  return pcall(require, "gitsigns")
end

-- Sidebar refresh after a status-affecting action. Deferred slightly so the
-- index has time to settle (gitsigns is async; the User GitSignsUpdate
-- autocmd in sidebar.lua handles the gitsigns path explicitly, but this
-- catches the no-gitsigns fallbacks too).
local function refresh_sidebar_soon()
  vim.defer_fn(function()
    pcall(function() require("review.sidebar").refresh() end)
  end, 50)
end

function M.stage_hunk()
  if has_gitsigns() then
    require("gitsigns").stage_hunk()
  else
    vim.notify("review: gitsigns not available", vim.log.levels.WARN)
  end
  refresh_sidebar_soon()
end

function M.stage_range()
  if has_gitsigns() then
    local s = vim.fn.line("v")
    local e = vim.fn.line(".")
    if s > e then s, e = e, s end
    require("gitsigns").stage_hunk({ s, e })
  else
    vim.notify("review: gitsigns not available", vim.log.levels.WARN)
  end
  refresh_sidebar_soon()
end

-- Stage "the file" — context-aware:
--   - if cursor is in the sidebar, stage the file under cursor
--   - otherwise, stage the current buffer
function M.stage_file()
  if vim.bo.filetype == "review-sidebar" then
    require("review.sidebar").toggle_stage()
    return
  end
  if has_gitsigns() then
    require("gitsigns").stage_buffer()
  else
    local file = vim.fn.expand("%:p")
    vim.fn.system({ "git", "add", "--", file })
  end
  refresh_sidebar_soon()
end

-- Refresh the sidebar (re-reads `git status` / `git diff`). No-op if the
-- sidebar isn't currently open.
function M.refresh_sidebar()
  require("review.sidebar").refresh()
end

-- Open colored diff for "the file" — context-aware:
--   - if cursor is in the sidebar, open the diff for the file under cursor
--   - otherwise, open the diff for the current buffer's file
function M.open_diff_view()
  if vim.bo.filetype == "review-sidebar" then
    require("review.sidebar").open_diff()
    return
  end
  local file = vim.fn.expand("%:.")
  if file == "" then
    vim.notify("review: no file in current buffer", vim.log.levels.WARN)
    return
  end
  -- Pass nil for target_win → open_diff_for creates a rightbelow vsplit.
  require("review.sidebar").open_diff_for(file, nil)
end

function M.commit_batch()
  vim.ui.input({ prompt = "Commit reviewed: ", default = "reviewed: " }, function(msg)
    if not msg then return end
    msg = vim.trim(msg)
    if msg == "" or msg == "reviewed:" then
      vim.notify("review: empty message — commit aborted", vim.log.levels.WARN)
      return
    end
    local out = vim.fn.systemlist({ "git", "commit", "-m", msg })
    if vim.v.shell_error == 0 then
      vim.notify("review: " .. (out[#out] or "committed"))
    else
      vim.notify("review: commit failed: " .. table.concat(out, "\n"), vim.log.levels.ERROR)
    end
    -- Refresh sidebar if open.
    pcall(function() require("review.sidebar").refresh() end)
  end)
end

function M.undo_last_batch()
  vim.ui.select(
    { "Yes — git reset --soft HEAD~1", "No" },
    { prompt = "Undo last review commit (soft reset)?" },
    function(choice)
      if choice and choice:match("^Yes") then
        vim.fn.system({ "git", "reset", "--soft", "HEAD~1" })
        pcall(function() require("review.sidebar").refresh() end)
      end
    end)
end

function M.show_status()
  local out = vim.fn.systemlist({ "review-status" })
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, out)
  vim.bo[buf].modifiable = false
  local width = math.min(vim.o.columns - 4, 80)
  local height = math.min(vim.o.lines - 4, #out + 2)
  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " review-status ",
    title_pos = "center",
  })
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

function M.next_unreviewed_file()
  local out = vim.fn.systemlist({ "git", "diff", "--name-only", "HEAD" })
  if vim.v.shell_error ~= 0 or #out == 0 then
    vim.notify("review: no unreviewed files", vim.log.levels.INFO)
    return
  end
  local current = vim.fn.expand("%:p")
  local work = vim.env.GIT_WORK_TREE or vim.fn.getcwd()
  local idx = 1
  for i, f in ipairs(out) do
    if work .. "/" .. f == current then
      idx = (i % #out) + 1
      break
    end
  end
  vim.cmd("edit " .. vim.fn.fnameescape(work .. "/" .. out[idx]))
end

function M.statusline()
  if not in_review_shell() then return "" end
  local slug = vim.env.REVIEW_SLUG or "?"
  return "review:" .. slug
end

return M
