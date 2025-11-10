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
      ["<C-r>"] = "refresh",
      ["d"] = "describe",
      ["n"] = "new",
      ["c"] = "commit",
      ["x"] = "restore",
      ["l"] = "log",
      ["?"] = "help",
      ["<CR>"] = "show_diff",
      ["<Tab>"] = "toggle",
      ["p"] = "pull",
      ["P"] = "push",
    },
  },
}

-- Setup configuration
function M.setup(opts)
  opts = opts or {}
  M.values = vim.tbl_deep_extend("force", M.values, opts)
end

return M
