-- review.nvim — autoload + global keymaps + commands.
--
-- Activates only when nvim was launched from `review-shell` (i.e. when
-- $GIT_DIR points at a path under ~/.review/). Outside a review shell,
-- this plugin is a no-op.

if vim.g.loaded_review then return end
vim.g.loaded_review = 1

local function in_review_shell()
  local gd = vim.env.GIT_DIR
  return gd and gd:match("/%.review/") ~= nil
end

if not in_review_shell() then return end

local review = require("review")

-- Commands
vim.api.nvim_create_user_command("ReviewSidebar",      function() review.sidebar().toggle() end, {})
vim.api.nvim_create_user_command("ReviewStatus",       function() review.show_status() end, {})
vim.api.nvim_create_user_command("ReviewCommit",       function() review.commit_batch() end, {})
vim.api.nvim_create_user_command("ReviewUndo",         function() review.undo_last_batch() end, {})
vim.api.nvim_create_user_command("ReviewNextFile",     function() review.next_unreviewed_file() end, {})

-- Default keymaps. Each is opt-out via `vim.g.review_no_default_mappings = 1`.
if vim.g.review_no_default_mappings ~= 1 then
  local map = function(mode, lhs, rhs, desc)
    vim.keymap.set(mode, lhs, rhs, { silent = true, desc = desc })
  end
  map("n", "<leader>rr", function() review.sidebar().toggle() end, "review: toggle sidebar")
  map("n", "<leader>rd", review.open_diff_view,                    "review: open diff view")
  map("n", "<leader>rh", review.stage_hunk,                        "review: stage hunk")
  map("v", "<leader>rl", review.stage_range,                       "review: stage line range")
  map("n", "<leader>rf", review.stage_file,                        "review: stage file (context-aware)")
  map("n", "<leader>rc", review.commit_batch,                      "review: commit batch")
  map("n", "<leader>ru", review.refresh_sidebar,                   "review: refresh sidebar")
  map("n", "<leader>rZ", review.undo_last_batch,                   "review: undo last batch (prompts)")
  map("n", "<leader>rs", review.show_status,                       "review: status")
  map("n", "<leader>rn", review.next_unreviewed_file,              "review: next unreviewed file")
end
