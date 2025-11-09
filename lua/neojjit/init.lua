-- Main entry point for neojjit
local M = {}
local config = require("neojjit.config")
local status_view = require("neojjit.views.status")
local ansi = require("neojjit.ansi")
local jj = require("neojjit.commands.jj")
local help = require("neojjit.help")

-- Setup function called by user
function M.setup(opts)
  config.setup(opts)

  -- Setup ANSI highlight groups
  ansi.setup_highlight_groups()

  -- Create user commands
  vim.api.nvim_create_user_command("Neojjit", function()
    M.open()
  end, { desc = "Open neojjit status view" })

  if config.values.debug then
    vim.notify("[NEOJJIT SETUP] Initialized with debug mode enabled", vim.log.levels.INFO)
  end
end

-- Open status view
function M.open()
  status_view.open()
end

-- Close status view
function M.close()
  status_view.close()
end

-- Refresh status view
function M.refresh()
  status_view.refresh()
end

-- Toggle diff for file under cursor
function M.toggle()
  status_view.toggle()
end

-- Describe current change (edit commit message)
function M.describe()
  jj.describe(function()
    -- Refresh status view after description is updated
    status_view.refresh()
    
    -- If auto_close is false, re-open the status view
    if not config.values.auto_close then
      status_view.open()
    end
  end)
end

-- Create new change
function M.new()
  jj.new()
  -- Refresh status after new completes
  status_view.refresh()
end

-- Commit (describe + new)
function M.commit()
  jj.commit(function()
    -- Refresh status view after commit is completed
    status_view.refresh()
    
    -- If auto_close is false, re-open the status view
    if not config.values.auto_close then
      status_view.open()
    end
  end)
end

-- Restore (discard) changes for file(s)
function M.restore()
  status_view.restore()
end

-- Restore (discard) changes for visual selection
function M.restore_visual()
  -- Get the visual selection marks
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  status_view.restore(start_line, end_line)
end

-- Show help popup
function M.help()
  help.show()
end

-- Show log (stub for now)
function M.log()
  vim.notify("Log view not yet implemented", vim.log.levels.INFO)
end

return M
