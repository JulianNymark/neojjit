-- Status view for neojjit
local M = {}
local ui = require("neojjit.ui")
local jj = require("neojjit.commands.jj")
local config = require("neojjit.config")
local watcher = require("neojjit.watcher")
local ansi = require("neojjit.ansi")

-- Current state
local state = {
  bufnr = nil,
  working_copy = nil,
  changes = {},
  expanded = {},      -- Track which files have diffs expanded
  highlights = {},    -- Store ANSI highlights to apply after rendering
  line_metadata = {}, -- Map buffer line number to metadata { type, filename, diff_line, content }
}

-- Parse jj status output
local function parse_status(lines)
  local changes = {}
  local working_copy = "@ (unknown)"

  -- Compile regex patterns once
  local file_change_re = vim.regex('^\\([AMD]\\)\\s\\+\\(.\\+\\)$')
  local working_copy_re = vim.regex('^Working copy\\s\\+(@)\\s*:\\s*\\(.\\+\\)$')
  local wc_ids_re = vim.regex('^\\(\\S\\+\\)\\s\\+\\(\\S\\+\\)\\s\\+\\(.*\\)$')

  for _, line in ipairs(lines) do
    -- Parse file changes: "A filename" or "M filename" or "D filename"
    local match_start = file_change_re:match_str(line)
    if match_start then
      local status = line:sub(1, 1)
      local file = line:match("^[AMD]%s+(.+)$")
      if status and file then
        table.insert(changes, {
          status = status,
          file = file,
        })
      end
    end

    -- Parse working copy line: "Working copy  (@) : change_id commit_id description"
    match_start = working_copy_re:match_str(line)
    if match_start then
      local wc_info = line:match("^Working copy%s+%(@%)%s*:%s*(.+)$")
      if wc_info then
        -- Extract change_id and commit_id
        local change_id, commit_id, desc = wc_info:match("^(%S+)%s+(%S+)%s+(.*)$")
        if change_id and commit_id then
          working_copy = string.format("%s %s", change_id:sub(1, 8), commit_id:sub(1, 8))
          if desc and desc ~= "" then
            working_copy = working_copy .. " " .. desc
          end
        end
      end
    end
  end

  if config.values.debug then
    vim.notify(
      string.format("[STATUS] Parsed %d changes, working copy: %s", #changes, working_copy),
      vim.log.levels.DEBUG
    )
  end

  return changes, working_copy
end

-- Parse jj's native diff format and extract line mapping
-- Format: "   old_num    new_num: content" or "        new_num: content" (added)
-- Returns table of { buffer_line -> { type, file_line, content, filename } }
local function parse_diff_metadata(diff_lines, start_buffer_line, filename)
  local metadata = {}

  -- Compile regex patterns once
  local header_re = vim.regex('^\\w\\+ .* file .\\+:')
  local header_added_re = vim.regex('^Added .* file')
  local header_deleted_re = vim.regex('^Deleted .* file')
  local context_colon_re = vim.regex('^\\s*\\(\\d\\+\\)\\s\\+\\(\\d\\+\\): \\(.*\\)$')
  local context_no_colon_re = vim.regex('^\\(\\d\\+\\)\\s\\+\\(\\d\\+\\)\\s\\(.*\\)$')
  local added_colon_re = vim.regex('^\\s\\+\\(\\d\\+\\): \\(.*\\)$')
  local added_no_colon_re = vim.regex('^\\s\\+\\(\\d\\+\\)\\s\\(.*\\)$')
  local removed_re = vim.regex('^\\s*\\(\\d\\+\\)\\s\\+: \\(.*\\)$')

  for i, line in ipairs(diff_lines) do
    local buffer_line = start_buffer_line + i

    if config.values.debug then
      vim.notify(string.format("[PARSE] Line %d (buf %d): '%s'", i, buffer_line, line:sub(1, 50)), vim.log.levels.DEBUG)
    end

    -- Check if this is a header line
    if header_re:match_str(line) or header_added_re:match_str(line) or header_deleted_re:match_str(line) then
      metadata[buffer_line] = {
        type = "header",
        filename = filename,
        content = line,
      }
    else
      -- Try Format 1 (with colon): "   old    new: content"
      local match = context_colon_re:match_str(line)
      if match then
        local old_num, new_num, content = line:match("^%s*(%d+)%s+(%d+): (.*)$")
        metadata[buffer_line] = {
          type = "context",
          filename = filename,
          file_line = tonumber(new_num),
          content = content,
        }
        if config.values.debug then
          vim.notify(string.format("[PARSE] Context (fmt1) %d: old=%s new=%s", buffer_line, old_num, new_num),
            vim.log.levels.DEBUG)
        end
      else
        -- Try Format 2 (difftastic): "old  new content"
        match = context_no_colon_re:match_str(line)
        if match then
          local old_num, new_num, content = line:match("^(%d+)%s+(%d+)%s(.*)$")
          metadata[buffer_line] = {
            type = "context",
            filename = filename,
            file_line = tonumber(new_num),
            content = content,
          }
          if config.values.debug then
            vim.notify(string.format("[PARSE] Context (difft) %d: old=%s new=%s", buffer_line, old_num, new_num),
              vim.log.levels.DEBUG)
          end
        else
          -- Try added line with colon
          match = added_colon_re:match_str(line)
          if match and not line:match("^%s*%d+%s+%d+:") then
            local new_num, content = line:match("^%s+(%d+): (.*)$")
            metadata[buffer_line] = {
              type = "added",
              filename = filename,
              file_line = tonumber(new_num),
              content = content,
            }
            if config.values.debug then
              vim.notify(string.format("[PARSE] Added (fmt1) %d: new=%s", buffer_line, new_num), vim.log.levels.DEBUG)
            end
          else
            -- Try added line without colon (difftastic)
            match = added_no_colon_re:match_str(line)
            if match and not line:match("^%d+%s+%d+%s") then
              local new_num, content = line:match("^%s+(%d+)%s(.*)$")
              metadata[buffer_line] = {
                type = "added",
                filename = filename,
                file_line = tonumber(new_num),
                content = content,
              }
              if config.values.debug then
                vim.notify(string.format("[PARSE] Added (difft) %d: new=%s", buffer_line, new_num), vim.log.levels.DEBUG)
              end
            else
              -- Try removed line (only old number)
              match = removed_re:match_str(line)
              if match then
                local old_num, content = line:match("^%s*(%d+)%s+: (.*)$")
                metadata[buffer_line] = {
                  type = "removed",
                  filename = filename,
                  content = content,
                }
                if config.values.debug then
                  vim.notify(string.format("[PARSE] Removed %d: old=%s", buffer_line, old_num), vim.log.levels.DEBUG)
                end
              else
                -- Other line
                metadata[buffer_line] = {
                  type = "other",
                  filename = filename,
                  content = line,
                }
              end
            end
          end
        end
      end
    end
  end

  if config.values.debug then
    vim.notify(
      string.format("[PARSE] Parsed %d metadata entries for %s", vim.tbl_count(metadata), filename),
      vim.log.levels.DEBUG
    )
  end

  return metadata
end

-- Generate buffer content
local function generate_content()
  local lines = {}
  state.highlights = {}    -- Reset highlights
  state.line_metadata = {} -- Reset line metadata

  -- Header with keybindings hint
  table.insert(lines, "Hint: <Tab> toggle | d describe | n new | c commit | x discard | q quit | ? help")
  table.insert(lines, "")

  -- Working copy info
  if state.working_copy then
    table.insert(lines, string.format("Working copy: %s", state.working_copy))
  else
    table.insert(lines, "Working copy: @ (no description set)")
  end
  table.insert(lines, "")

  -- Changes section
  table.insert(lines, string.format("Changes (%d)", #state.changes))
  if #state.changes > 0 then
    for _, change in ipairs(state.changes) do
      local status_text = change.status
      if change.status == "A" then
        status_text = "added"
      elseif change.status == "M" then
        status_text = "modified"
      elseif change.status == "D" then
        status_text = "deleted"
      end

      local file_line_num = #lines + 1
      table.insert(lines, string.format("%-10s %s", status_text, change.file))

      -- Store metadata for file line
      state.line_metadata[file_line_num] = {
        type = "file",
        filename = change.file,
      }

      -- If this file is expanded, show the diff
      if state.expanded[change.file] then
        -- Get display diff (with colors)
        local diff_lines = jj.diff(change.file)
        if diff_lines then
          -- Parse ANSI codes from diff lines
          local start_line = #lines
          local cleaned_lines, highlights = ansi.parse_lines(diff_lines, start_line)

          -- Parse diff metadata from cleaned lines
          local diff_metadata = parse_diff_metadata(cleaned_lines, start_line, change.file)

          -- Merge diff metadata into state
          for line_num, meta in pairs(diff_metadata) do
            state.line_metadata[line_num] = meta
          end

          -- Add cleaned lines to buffer
          for _, line in ipairs(cleaned_lines) do
            table.insert(lines, line)
          end

          -- Store highlights to apply later
          for _, hl in ipairs(highlights) do
            table.insert(state.highlights, hl)
          end
        end
      end
    end
  else
    table.insert(lines, "  (no changes)")
  end

  return lines
end

-- Extract filename from a status line
local function extract_filename(line)
  -- Compile patterns once (they're static)
  local patterns = {
    vim.regex('^added\\s\\+\\(.\\+\\)$'),
    vim.regex('^modified\\s\\+\\(.\\+\\)$'),
    vim.regex('^deleted\\s\\+\\(.\\+\\)$'),
  }

  for _, pattern in ipairs(patterns) do
    local match = pattern:match_str(line)
    if match then
      -- Extract the filename part
      return line:match("^%w+%s+(.+)$")
    end
  end

  return nil
end

-- Toggle diff for file under cursor
function M.toggle()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  -- Get current line
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(state.bufnr, line_num - 1, line_num, false)[1]

  -- Extract filename from status line (format: "status     filename")
  local filename = extract_filename(line)

  if filename then
    -- Toggle expansion state
    state.expanded[filename] = not state.expanded[filename]

    if config.values.debug then
      vim.notify(
        string.format("[STATUS] Toggled diff for %s: %s", filename, state.expanded[filename]),
        vim.log.levels.DEBUG
      )
    end

    -- Re-render
    local content = generate_content()
    ui.render(state.bufnr, content)

    -- Apply ANSI highlights with dedicated namespace for status view
    if #state.highlights > 0 then
      local status_namespace = vim.api.nvim_create_namespace("neojjit_status_ansi")
      ansi.apply_highlights(state.bufnr, state.highlights, status_namespace)
    end
  end
end

-- Remove added lines from a file (restore to previous state)
local function remove_lines_from_file(filename, line_numbers)
  -- Read the file
  local file_path = vim.fn.getcwd() .. "/" .. filename
  local file = io.open(file_path, "r")
  if not file then
    vim.notify(string.format("Could not open file: %s", filename), vim.log.levels.ERROR)
    return false
  end

  local file_lines = {}
  for line in file:lines() do
    table.insert(file_lines, line)
  end
  file:close()

  -- Remove lines in reverse order to preserve line numbers
  table.sort(line_numbers, function(a, b)
    return a > b
  end)
  for _, line_num in ipairs(line_numbers) do
    if line_num > 0 and line_num <= #file_lines then
      table.remove(file_lines, line_num)
    end
  end

  -- Write the file back
  file = io.open(file_path, "w")
  if not file then
    vim.notify(string.format("Could not write file: %s", filename), vim.log.levels.ERROR)
    return false
  end

  for _, line in ipairs(file_lines) do
    file:write(line .. "\n")
  end
  file:close()

  return true
end

-- Restore (discard) changes for file(s) or specific diff lines
-- start_line and end_line are optional for visual mode selection
function M.restore(start_line, end_line)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local files_to_restore = {}
  local diff_lines_to_delete = {} -- { filename -> {line_numbers} }

  -- Determine line range
  local first_line, last_line
  if start_line and end_line then
    first_line = math.min(start_line, end_line)
    last_line = math.max(start_line, end_line)
  else
    first_line = vim.api.nvim_win_get_cursor(0)[1]
    last_line = first_line
  end

  -- Check if any selected lines are in diff sections
  local has_diff_lines = false
  local diff_filenames = {} -- Track which files are involved in the diff selection
  for line_num = first_line, last_line do
    local meta = state.line_metadata[line_num]

    if config.values.debug then
      vim.notify(
        string.format("[RESTORE] Line %d metadata: %s", line_num, meta and meta.type or "nil"),
        vim.log.levels.DEBUG
      )
    end

    if meta and meta.type == "added" then
      has_diff_lines = true
      local filename = meta.filename
      if not diff_lines_to_delete[filename] then
        diff_lines_to_delete[filename] = {}
      end
      table.insert(diff_lines_to_delete[filename], meta.file_line)
      diff_filenames[filename] = true
    elseif meta and (meta.type == "context" or meta.type == "removed" or meta.type == "header" or meta.type == "other") and meta.filename then
      -- Track files that have diff context selected, even if not "added" lines
      diff_filenames[meta.filename] = true
    end
  end

  if config.values.debug then
    vim.notify(
      string.format("[RESTORE] Total metadata entries: %d", vim.tbl_count(state.line_metadata)),
      vim.log.levels.DEBUG
    )
    vim.notify(string.format("[RESTORE] Has diff lines: %s", has_diff_lines), vim.log.levels.DEBUG)
    local filenames = {}
    for fname, _ in pairs(diff_filenames) do
      table.insert(filenames, fname)
    end
    vim.notify(string.format("[RESTORE] Diff filenames: %s", table.concat(filenames, ", ")), vim.log.levels.DEBUG)
  end

  -- If we have specific added lines to delete, handle partial deletion
  if has_diff_lines then
    local file_list = {}
    local total_lines = 0
    for filename, line_nums in pairs(diff_lines_to_delete) do
      table.insert(file_list, string.format("%s (%d lines)", filename, #line_nums))
      total_lines = total_lines + #line_nums
    end

    local message = string.format("Discard %d added line(s) from:\n  %s", total_lines, table.concat(file_list, "\n  "))
    local choice = vim.fn.confirm(message, "&Yes\n&No", 2)

    if choice == 1 then
      local success = true
      for filename, line_nums in pairs(diff_lines_to_delete) do
        if not remove_lines_from_file(filename, line_nums) then
          success = false
        end
      end

      if success then
        vim.notify(string.format("Deleted %d line(s)", total_lines), vim.log.levels.INFO)
        -- Refresh the view
        vim.defer_fn(function()
          M.refresh()
        end, 100)
      end
    else
      vim.notify("Cancelled", vim.log.levels.INFO)
    end
    return
  end

  -- Otherwise, handle file-level deletion
  local lines = vim.api.nvim_buf_get_lines(state.bufnr, first_line - 1, last_line, false)
  for _, line in ipairs(lines) do
    local filename = extract_filename(line)
    if filename then
      table.insert(files_to_restore, filename)
    end
  end

  -- If we didn't find files in file lines, check if we have diff context selected
  if #files_to_restore == 0 and next(diff_filenames) ~= nil then
    for filename, _ in pairs(diff_filenames) do
      table.insert(files_to_restore, filename)
    end
  end

  -- If we found files, ask for confirmation and restore them
  if #files_to_restore > 0 then
    local file_list = table.concat(files_to_restore, "\n  ")
    local message = string.format("Discard changes for:\n  %s", file_list)
    local choice = vim.fn.confirm(message, "&Yes\n&No", 2)

    if choice == 1 then
      local result = jj.restore(files_to_restore)
      if result then
        -- Remove files from expanded state
        for _, file in ipairs(files_to_restore) do
          state.expanded[file] = nil
        end
        -- Refresh the view
        M.refresh()
      end
    else
      vim.notify("Cancelled", vim.log.levels.INFO)
    end
  else
    vim.notify("No file or diff lines found in selection", vim.log.levels.WARN)
  end
end

-- Restore (discard) changes for file(s) with --ignore-immutable flag
-- start_line and end_line are optional for visual mode selection
function M.restore_force(start_line, end_line)
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local files_to_restore = {}
  local diff_lines_to_delete = {} -- { filename -> {line_numbers} }

  -- Determine line range
  local first_line, last_line
  if start_line and end_line then
    first_line = math.min(start_line, end_line)
    last_line = math.max(start_line, end_line)
  else
    first_line = vim.api.nvim_win_get_cursor(0)[1]
    last_line = first_line
  end

  -- Check if any selected lines are in diff sections
  local has_diff_lines = false
  local diff_filenames = {} -- Track which files are involved in the diff selection
  for line_num = first_line, last_line do
    local meta = state.line_metadata[line_num]

    if config.values.debug then
      vim.notify(
        string.format("[RESTORE_FORCE] Line %d metadata: %s", line_num, meta and meta.type or "nil"),
        vim.log.levels.DEBUG
      )
    end

    if meta and meta.type == "added" then
      has_diff_lines = true
      local filename = meta.filename
      if not diff_lines_to_delete[filename] then
        diff_lines_to_delete[filename] = {}
      end
      table.insert(diff_lines_to_delete[filename], meta.file_line)
      diff_filenames[filename] = true
    elseif meta and (meta.type == "context" or meta.type == "removed" or meta.type == "header" or meta.type == "other") and meta.filename then
      -- Track files that have diff context selected, even if not "added" lines
      diff_filenames[meta.filename] = true
    end
  end

  if config.values.debug then
    vim.notify(
      string.format("[RESTORE_FORCE] Total metadata entries: %d", vim.tbl_count(state.line_metadata)),
      vim.log.levels.DEBUG
    )
    vim.notify(string.format("[RESTORE_FORCE] Has diff lines: %s", has_diff_lines), vim.log.levels.DEBUG)
    local filenames = {}
    for fname, _ in pairs(diff_filenames) do
      table.insert(filenames, fname)
    end
    vim.notify(string.format("[RESTORE_FORCE] Diff filenames: %s", table.concat(filenames, ", ")), vim.log.levels.DEBUG)
  end

  -- If we have specific added lines to delete, handle partial deletion
  if has_diff_lines then
    local file_list = {}
    local total_lines = 0
    for filename, line_nums in pairs(diff_lines_to_delete) do
      table.insert(file_list, string.format("%s (%d lines)", filename, #line_nums))
      total_lines = total_lines + #line_nums
    end

    local message = string.format("Discard (force) %d added line(s) from:\n  %s", total_lines,
      table.concat(file_list, "\n  "))
    local choice = vim.fn.confirm(message, "&Yes\n&No", 2)

    if choice == 1 then
      local success = true
      for filename, line_nums in pairs(diff_lines_to_delete) do
        if not remove_lines_from_file(filename, line_nums) then
          success = false
        end
      end

      if success then
        vim.notify(string.format("Deleted %d line(s)", total_lines), vim.log.levels.INFO)
        -- Refresh the view
        vim.defer_fn(function()
          M.refresh()
        end, 100)
      end
    else
      vim.notify("Cancelled", vim.log.levels.INFO)
    end
    return
  end

  -- Otherwise, handle file-level deletion
  local lines = vim.api.nvim_buf_get_lines(state.bufnr, first_line - 1, last_line, false)
  for _, line in ipairs(lines) do
    local filename = extract_filename(line)
    if filename then
      table.insert(files_to_restore, filename)
    end
  end

  -- If we didn't find files in file lines, check if we have diff context selected
  if #files_to_restore == 0 and next(diff_filenames) ~= nil then
    for filename, _ in pairs(diff_filenames) do
      table.insert(files_to_restore, filename)
    end
  end

  -- If we found files, ask for confirmation and restore them
  if #files_to_restore > 0 then
    local file_list = table.concat(files_to_restore, "\n  ")
    local message = string.format("Discard changes (force) for:\n  %s", file_list)
    local choice = vim.fn.confirm(message, "&Yes\n&No", 2)

    if choice == 1 then
      local result = jj.restore_force(files_to_restore)
      if result then
        -- Remove files from expanded state
        for _, file in ipairs(files_to_restore) do
          state.expanded[file] = nil
        end
        -- Refresh the view
        M.refresh()
      end
    else
      vim.notify("Cancelled", vim.log.levels.INFO)
    end
  else
    vim.notify("No file or diff lines found in selection", vim.log.levels.WARN)
  end
end

-- Handle force prefix key (normal mode)
local function handle_force_prefix()
  vim.notify("Force: ", vim.log.levels.INFO)
  local ok, char = pcall(vim.fn.getcharstr)
  if not ok or char == "\27" then -- \27 is ESC
    vim.notify("Cancelled", vim.log.levels.INFO)
    return
  end
  
  -- Map force commands
  local force_commands = {
    x = function() M.restore_force() end,
  }
  
  local cmd = force_commands[char]
  if cmd then
    cmd()
  else
    vim.notify(string.format("No force command for '%s'", char), vim.log.levels.WARN)
  end
end

-- Handle force prefix key (visual mode)
local function handle_force_prefix_visual()
  vim.notify("Force: ", vim.log.levels.INFO)
  local ok, char = pcall(vim.fn.getcharstr)
  if not ok or char == "\27" then -- \27 is ESC
    vim.notify("Cancelled", vim.log.levels.INFO)
    return
  end
  
  -- Get the visual selection marks
  local start_line = vim.fn.line("'<")
  local end_line = vim.fn.line("'>")
  
  -- Map force commands
  local force_commands = {
    x = function() M.restore_force(start_line, end_line) end,
  }
  
  local cmd = force_commands[char]
  if cmd then
    cmd()
  else
    vim.notify(string.format("No force command for '%s'", char), vim.log.levels.WARN)
  end
end

M.handle_force_prefix = handle_force_prefix
M.handle_force_prefix_visual = handle_force_prefix_visual

-- Refresh status data
function M.refresh()
  if config.values.debug then
    vim.notify("[STATUS] Refreshing status", vim.log.levels.DEBUG)
  end

  -- Get status (returns both changes and working copy info)
  local status_lines = jj.status()
  if status_lines then
    state.changes, state.working_copy = parse_status(status_lines)
  end

  -- Re-render if buffer exists
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    local content = generate_content()
    ui.render(state.bufnr, content)

    -- Apply ANSI highlights with dedicated namespace for status view
    if #state.highlights > 0 then
      local status_namespace = vim.api.nvim_create_namespace("neojjit_status_ansi")
      ansi.apply_highlights(state.bufnr, state.highlights, status_namespace)
    end
  end

  vim.notify("Status refreshed", vim.log.levels.INFO)
end

-- Open status view
function M.open()
  -- Create buffer if it doesn't exist
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    state.bufnr = ui.create_buffer("status", {
      filetype = "neojjit",
      mappings = config.values.mappings.status,
    })

    -- Set up keymaps
    ui.set_mappings(state.bufnr, config.values.mappings.status)

    -- Map 'f' to force prefix handler
    vim.api.nvim_buf_set_keymap(
      state.bufnr,
      "n",
      "f",
      "<cmd>lua require('neojjit.views.status').handle_force_prefix()<CR>",
      { noremap = true, silent = true }
    )

    -- Add visual mode mapping for restore
    -- Use :<C-u> to clear the range and avoid Ex mode issues
    vim.api.nvim_buf_set_keymap(
      state.bufnr,
      "v",
      "x",
      ":<C-u>lua require('neojjit').restore_visual()<CR>",
      { noremap = true, silent = true }
    )

    -- Add visual mode mapping for force prefix
    vim.api.nvim_buf_set_keymap(
      state.bufnr,
      "v",
      "f",
      ":<C-u>lua require('neojjit.views.status').handle_force_prefix_visual()<CR>",
      { noremap = true, silent = true }
    )
  end

  -- Open buffer in window (full screen)
  -- Close all other windows first
  vim.cmd("only")
  ui.open_buffer(state.bufnr, {})

  -- Load and render content
  M.refresh()

  -- Move cursor to first change or "(no changes)" line
  local cursor_line = 6
  vim.api.nvim_win_set_cursor(0, { cursor_line, 0 })

  -- Start file watcher for auto-refresh
  -- Watches the working directory for any file changes
  local cwd = vim.fn.getcwd()
  watcher.start(cwd, function()
    M.refresh()
  end)
end

-- Close status view
function M.close()
  watcher.stop()
  ui.close_buffer("status")
  state.bufnr = nil
end

return M
