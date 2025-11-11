-- Main entry point for neojjit
local M = {}
local config = require("neojjit.config")
local status_view = require("neojjit.views.status")
local log_view = require("neojjit.views.log")
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

-- Restore (discard) changes for file(s) with --ignore-immutable flag
function M.restore_force()
  status_view.restore_force()
end

-- Restore (discard) changes for visual selection
function M.restore_visual()
  -- Get the visual selection marks
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  status_view.restore(start_line, end_line)
end

-- Restore (discard) changes for visual selection with --ignore-immutable flag
function M.restore_force_visual()
  -- Get the visual selection marks
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  status_view.restore_force(start_line, end_line)
end

-- Show help popup
function M.help()
  help.show()
end

-- Show log help popup
function M.log_help()
  help.show("log")
end

-- Show log view
function M.log()
  log_view.open()
end

-- Log view: copy change ID
function M.log_copy_change_id()
  log_view.copy_change_id()
end

-- Log view: copy commit hash
function M.log_copy_commit_hash()
  log_view.copy_commit_hash()
end

-- Log view: set bookmark
function M.log_set_bookmark()
  log_view.set_bookmark()
end

-- Log view: set bookmark with --allow-backwards flag
function M.log_set_bookmark_force()
  log_view.set_bookmark_force()
end

-- Log view: edit change
function M.log_edit()
  log_view.edit_change()
end

-- Log view: edit change with --ignore-immutable flag
function M.log_edit_force()
  log_view.edit_change_force()
end

-- Log view: new change
function M.log_new()
  log_view.new_change()
end

-- Log view: describe change
function M.log_describe()
  log_view.describe_change()
end

-- Log view: abandon change
function M.log_abandon()
  log_view.abandon_change()
end

-- Log view: close
function M.log_close()
  log_view.close()
end

-- Log view: refresh
function M.log_refresh()
  log_view.refresh()
end

-- Log view: next entry
function M.log_next_entry()
  log_view.next_entry()
end

-- Log view: previous entry
function M.log_prev_entry()
  log_view.prev_entry()
end

-- Push changes to remote
function M.push()
  jj.push()
  -- Refresh status after push completes
  status_view.refresh()
end

-- Pull changes from remote
function M.pull()
  jj.pull()
  -- Refresh status after pull completes
  status_view.refresh()
end

-- Undo last operation (status view)
function M.undo()
  jj.undo()
  -- Refresh status after undo completes
  status_view.refresh()
end

-- Undo last operation (log view)
function M.log_undo()
  jj.undo()
  -- Refresh log after undo completes
  log_view.refresh()
end

-- Push changes to remote (log view)
function M.log_push()
  jj.push()
  -- Refresh log after push completes
  log_view.refresh()
end

-- Pull changes from remote (log view)
function M.log_pull()
  jj.pull()
  -- Refresh log after pull completes
  log_view.refresh()
end

return M
