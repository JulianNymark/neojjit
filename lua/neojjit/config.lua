-- Configuration for neojjit
local M = {}

-- Default configuration
M.values = {
  debug = false,
  -- Use difftastic for diffs if available
  -- When enabled, neojjit will configure difftastic's width dynamically
  -- via jj's --config flag (runtime-only, does not modify any config files)
  use_difftastic = true,
  auto_close = false, -- Auto-close status view after operations (describe, commit, etc)
  mappings = {
    status = {
      ["q"] = "close",
      ["<C-r>"] = "redo",
      ["<C-S-r>"] = "refresh",
      ["d"] = "describe",
      ["n"] = "new",
      ["c"] = "commit",
      ["x"] = "restore",
      ["u"] = "undo",
      ["l"] = "log",
      ["?"] = "help",
      ["<CR>"] = "show_diff",
      ["<Tab>"] = "toggle",
      ["p"] = "pull",
      ["P"] = "push",
    },
    log = {
      ["q"] = "log_close",
      ["<C-r>"] = "log_redo",
      ["<C-S-r>"] = "log_refresh",
      ["d"] = "log_describe",
      ["y"] = "log_copy_change_id",
      ["g"] = "log_copy_commit_hash",
      ["b"] = "log_set_bookmark",
      ["e"] = "log_edit",
      ["n"] = "log_new",
      ["x"] = "log_abandon",
      ["u"] = "log_undo",
      ["p"] = "log_pull",
      ["P"] = "log_push",
      ["?"] = "log_help",
    },
  },
}

-- Setup configuration
function M.setup(opts)
  opts = opts or {}
  M.values = vim.tbl_deep_extend("force", M.values, opts)
end

return M
