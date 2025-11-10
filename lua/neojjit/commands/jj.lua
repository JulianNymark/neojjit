-- jj CLI wrapper
local M = {}
local config = require("neojjit.config")

-- Execute jj command
function M.execute(args, opts)
  opts = opts or {}

  local cmd = { "jj" }
  vim.list_extend(cmd, args)

  if config.values.debug then
    vim.notify(string.format("[JJ CMD] %s", table.concat(cmd, " ")), vim.log.levels.DEBUG)
  end

  local result = vim.fn.systemlist(cmd)
  local exit_code = vim.v.shell_error

  if config.values.debug then
    vim.notify(string.format("[JJ CMD] Exit code: %d, Lines: %d", exit_code, #result), vim.log.levels.DEBUG)
  end

  if exit_code ~= 0 and not opts.ignore_error then
    vim.notify(string.format("jj command failed: %s", table.concat(result, "\n")), vim.log.levels.ERROR)
    return nil
  end

  return result
end

-- Get jj status
function M.status()
  return M.execute({ "status" })
end

-- Get working copy info
function M.show_working_copy()
  return M.execute({ "log", "-r", "@", "--no-graph" })
end

-- Describe current change
function M.describe(callback)
  -- Get current description
  local current_desc = M.execute({ "log", "-r", "@", "--no-graph", "-T", "description" })
  local initial_lines = current_desc or { "" }

  -- Create a new buffer for editing the description
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
  vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(bufnr, "filetype", "gitcommit")
  vim.api.nvim_buf_set_name(bufnr, "JJ_DESCRIPTION")

  -- Save the original buffer
  local original_bufnr = vim.api.nvim_get_current_buf()

  -- Open the buffer in current window
  vim.api.nvim_set_current_buf(bufnr)

  -- Set up autocmd to handle save
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      -- Get the description from buffer
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Remove comment lines (lines starting with # or JJ:)
      local comment_re = vim.regex('^\\(#\\|JJ:\\)')
      local filtered_lines = {}
      for _, line in ipairs(lines) do
        if not comment_re:match_str(line) then
          table.insert(filtered_lines, line)
        end
      end

      local description = table.concat(filtered_lines, "\n")

      -- Trim whitespace from beginning and end
      description = vim.trim(description)

      if description == "" then
        vim.notify("Empty description, aborting", vim.log.levels.WARN)
        return
      end

      -- Execute jj describe with the message
      local result = M.execute({ "describe", "-m", description })

      if result then
        vim.notify("Description updated", vim.log.levels.INFO)
        -- Close the description buffer
        vim.api.nvim_buf_delete(bufnr, { force = true })

        -- Call callback if provided (should refresh and potentially re-open status view)
        if callback then
          callback()
        else
          -- If no callback, return to original buffer
          if vim.api.nvim_buf_is_valid(original_bufnr) then
            vim.api.nvim_set_current_buf(original_bufnr)
          end
        end
      else
        vim.notify("Failed to update description", vim.log.levels.ERROR)
      end
    end,
  })

  -- Set up autocmd to handle quit without save
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      -- Return to original buffer if still valid
      if vim.api.nvim_buf_is_valid(original_bufnr) then
        vim.api.nvim_set_current_buf(original_bufnr)
      end
    end,
  })

  -- Add instructions as comments
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, {
    "",
    "JJ: Saving (:w) will automatically close this buffer",
    "JJ: If you saved before you were finished describing you can invoke describe again",
  })

  -- Start in insert mode
  vim.cmd("startinsert")
end

-- Create new change
function M.new()
  local result = M.execute({ "new" })
  if result then
    vim.notify("Created new change", vim.log.levels.INFO)
  end
  return result
end

-- Commit (describe + new)
function M.commit(callback)
  -- Get current description
  local current_desc = M.execute({ "log", "-r", "@", "--no-graph", "-T", "description" })
  local initial_lines = current_desc or { "" }

  -- Create a new buffer for editing the description
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, initial_lines)
  vim.api.nvim_buf_set_option(bufnr, "buftype", "acwrite")
  vim.api.nvim_buf_set_option(bufnr, "filetype", "gitcommit")
  vim.api.nvim_buf_set_name(bufnr, "JJ_COMMIT")

  -- Save the original buffer
  local original_bufnr = vim.api.nvim_get_current_buf()

  -- Open the buffer in current window
  vim.api.nvim_set_current_buf(bufnr)

  -- Set up autocmd to handle save
  vim.api.nvim_create_autocmd("BufWriteCmd", {
    buffer = bufnr,
    callback = function()
      -- Get the description from buffer
      local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

      -- Remove comment lines
      local comment_re = vim.regex('^#')
      local filtered_lines = {}
      for _, line in ipairs(lines) do
        if not comment_re:match_str(line) then
          table.insert(filtered_lines, line)
        end
      end

      local description = table.concat(filtered_lines, "\n")

      -- Trim whitespace from beginning and end
      description = vim.trim(description)

      if description == "" then
        vim.notify("Empty description, aborting", vim.log.levels.WARN)
        return
      end

      -- Execute jj describe + new
      local desc_result = M.execute({ "describe", "-m", description })

      if desc_result then
        local new_result = M.execute({ "new" })
        if new_result then
          vim.notify("Commit completed", vim.log.levels.INFO)
          -- Close the commit buffer
          vim.api.nvim_buf_delete(bufnr, { force = true })

          -- Call callback if provided (should refresh and potentially re-open status view)
          if callback then
            callback()
          else
            -- If no callback, return to original buffer
            if vim.api.nvim_buf_is_valid(original_bufnr) then
              vim.api.nvim_set_current_buf(original_bufnr)
            end
          end
        else
          vim.notify("Failed to create new change", vim.log.levels.ERROR)
        end
      else
        vim.notify("Failed to update description", vim.log.levels.ERROR)
      end
    end,
  })

  -- Set up autocmd to handle quit without save
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = bufnr,
    once = true,
    callback = function()
      -- Return to original buffer if still valid
      if vim.api.nvim_buf_is_valid(original_bufnr) then
        vim.api.nvim_set_current_buf(original_bufnr)
      end
    end,
  })

  -- Add instructions as comments
  vim.api.nvim_buf_set_lines(bufnr, -1, -1, false, {
    "",
    "# Edit the commit message above",
    "# Save and close (:wq) to commit, or just close (:q) to cancel",
  })

  -- Start in insert mode
  vim.cmd("startinsert")
end

-- Get diff for a file using difftastic or regular diff
function M.diff(filepath)
  local has_difft = vim.fn.executable("difft") == 1
  local use_difft = config.values.use_difftastic and has_difft

  local args = { "diff" }
  local opts = {}

  if use_difft then
    local width = vim.api.nvim_win_get_width(0) - 4

    -- Set jj config for difft width using --config flag (runtime-only, non-persistent)
    table.insert(args, 1, "--config")
    table.insert(
      args,
      2,
      string.format('merge-tools.difft.diff-args=["--color=always", "--width=%d", "$left", "$right"]', width)
    )
    table.insert(args, "--tool")
    table.insert(args, "difft")
  else
    -- Use regular diff with color
    table.insert(args, "--color=always")
  end

  -- Add filepath if provided
  if filepath and filepath ~= "" then
    table.insert(args, filepath)
  end

  local result = M.execute(args, opts)

  if result and #result > 0 then
    -- Add a blank line before the diff for readability
    table.insert(result, 1, "")
  end

  return result
end

-- Get diff in git format (for patch processing)
function M.diff_git(filepath)
  local args = { "diff", "--git", "--no-pager" }

  -- Add filepath if provided
  if filepath and filepath ~= "" then
    table.insert(args, filepath)
  end

  return M.execute(args)
end

-- Restore (discard changes) for one or more files
function M.restore(filepaths)
  if type(filepaths) == "string" then
    filepaths = { filepaths }
  end

  local args = { "restore" }
  vim.list_extend(args, filepaths)

  local result = M.execute(args)
  if result then
    local file_list = table.concat(filepaths, ", ")
    vim.notify(string.format("Restored: %s", file_list), vim.log.levels.INFO)
  end
  return result
end

-- Restore (discard changes) for one or more files with --ignore-immutable flag
function M.restore_force(filepaths)
  if type(filepaths) == "string" then
    filepaths = { filepaths }
  end

  local args = { "restore", "--ignore-immutable" }
  vim.list_extend(args, filepaths)

  local result = M.execute(args)
  if result then
    local file_list = table.concat(filepaths, ", ")
    vim.notify(string.format("Restored (force): %s", file_list), vim.log.levels.INFO)
  end
  return result
end

-- Push changes to remote
function M.push()
  local result = M.execute({ "git", "push" })
  if result then
    vim.notify("Pushed to remote", vim.log.levels.INFO)
  end
  return result
end

-- Pull changes from remote
function M.pull()
  local result = M.execute({ "git", "fetch" })
  if result then
    vim.notify("Pulled from remote", vim.log.levels.INFO)
  end
  return result
end

-- Get log entries with color output (similar to terminal)
function M.log(revset)
  revset = revset or "ancestors(immutable_heads().., 5)"

  local args = { "log", "-r", revset, "--color=always" }
  return M.execute(args)
end

-- Set bookmark on a specific change
function M.set_bookmark(bookmark_name, change_id)
  local args = { "bookmark", "set", bookmark_name, "-r", change_id }
  local result = M.execute(args)
  if result then
    vim.notify(string.format("Set bookmark '%s' on %s", bookmark_name, change_id), vim.log.levels.INFO)
  end
  return result
end

-- Set bookmark on a specific change with --allow-backwards flag
function M.set_bookmark_force(bookmark_name, change_id)
  local args = { "bookmark", "set", bookmark_name, "-r", change_id, "--allow-backwards" }
  local result = M.execute(args)
  if result then
    vim.notify(string.format("Set bookmark (force) '%s' on %s", bookmark_name, change_id), vim.log.levels.INFO)
  end
  return result
end

-- Edit a specific change (set working copy to that change)
function M.edit(change_id)
  local args = { "edit", change_id }
  local result = M.execute(args)
  if result then
    vim.notify(string.format("Now editing %s", change_id), vim.log.levels.INFO)
  end
  return result
end

-- Edit a specific change with --ignore-immutable flag
function M.edit_force(change_id)
  local args = { "edit", change_id, "--ignore-immutable" }
  local result = M.execute(args)
  if result then
    vim.notify(string.format("Now editing (force) %s", change_id), vim.log.levels.INFO)
  end
  return result
end

-- Create new change on top of a specific change
function M.new_on_change(change_id)
  local args = { "new", change_id }
  local result = M.execute(args)
  if result then
    vim.notify(string.format("Created new change on %s", change_id), vim.log.levels.INFO)
  end
  return result
end

-- Undo the last operation
function M.undo()
  local result = M.execute({ "undo" })
  if result then
    vim.notify("Undid last operation", vim.log.levels.INFO)
  end
  return result
end

return M
