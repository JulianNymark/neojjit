-- Configuration for neojjit
local M = {}

-- Default configuration
M.values = {
  debug = false,
  use_difftastic = true, -- Use difftastic for diffs if available
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
    },
  },
}

-- Setup configuration
function M.setup(opts)
  opts = opts or {}
  M.values = vim.tbl_deep_extend("force", M.values, opts)
end

return M
