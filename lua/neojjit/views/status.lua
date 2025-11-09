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

  for _, line in ipairs(lines) do
    -- Parse file changes: "A filename" or "M filename" or "D filename"
    -- Only match single-letter status codes at start of line
    local status, file = line:match("^([AMD])%s+(.+)$")
    if status and file then
      table.insert(changes, {
        status = status,
        file = file,
      })
    end

    -- Parse working copy line: "Working copy  (@) : change_id commit_id description"
    -- Example: "Working copy  (@) : ruzrnrvn d6524489 (no description set)"
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

  if config.values.debug then
    vim.notify(string.format("[STATUS] Parsed %d changes, working copy: %s", #changes, working_copy),
      vim.log.levels.DEBUG)
  end

  return changes, working_copy
end

-- Parse jj's native diff format and extract line mapping
-- Format: "   old_num    new_num: content" or "        new_num: content" (added)
-- Returns table of { buffer_line -> { type, file_line, content, filename } }
local function parse_diff_metadata(diff_lines, start_buffer_line, filename)
  local metadata = {}

  for i, line in ipairs(diff_lines) do
    local buffer_line = start_buffer_line + i

    if config.values.debug then
      vim.notify(string.format("[PARSE] Line %d (buf %d): '%s'", i, buffer_line, line:sub(1, 50)), vim.log.levels.DEBUG)
    end

    -- Check if this is a header line (e.g., "Modified regular file test.txt:")
    if line:match("^%w+ .* file .+:") or line:match("^Added .* file") or line:match("^Deleted .* file") then
      metadata[buffer_line] = {
        type = "header",
        filename = filename,
        content = line,
      }
    else
      -- Try to parse different line formats:
      -- Format 1 (non-difftastic):
      --   Context line: "   old    new: content" (both line numbers with colon)
      --   Added line:   "        new: content" (only new line number with colon)
      --   Removed line: "   old     : content" (only old line number with colon)
      -- Format 2 (difftastic):
      --   Context line: "old  new content" (both line numbers, no colon)
      --   Added line:   "     new content" (only new line number, no colon)

      -- Try Format 1 first (with colon)
      local old_num, new_num, content = line:match("^%s*(%d+)%s+(%d+): (.*)$")
      if old_num and new_num then
        -- Context line with colon
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
        -- Try Format 2 (without colon) - difftastic
        old_num, new_num, content = line:match("^(%d+)%s+(%d+)%s(.*)$")
        if old_num and new_num then
          -- Context line from difftastic
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
          new_num, content = line:match("^%s+(%d+): (.*)$")
          if new_num and not line:match("^%s*%d+%s+%d+:") then
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
            new_num, content = line:match("^%s+(%d+)%s(.*)$")
            if new_num and not line:match("^%d+%s+%d+%s") then
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
              old_num, content = line:match("^%s*(%d+)%s+: (.*)$")
              if old_num then
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
    vim.notify(string.format("[PARSE] Parsed %d metadata entries for %s", vim.tbl_count(metadata), filename),
      vim.log.levels.DEBUG)
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

-- Toggle diff for file under cursor
function M.toggle()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  -- Get current line
  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  local line = vim.api.nvim_buf_get_lines(state.bufnr, line_num - 1, line_num, false)[1]

  -- Extract filename from status line (format: "status     filename")
  local filename = line:match("^added%s+(.+)$") or
    line:match("^modified%s+(.+)$") or
    line:match("^deleted%s+(.+)$")

  if filename then
    -- Toggle expansion state
    state.expanded[filename] = not state.expanded[filename]

    if config.values.debug then
      vim.notify(string.format("[STATUS] Toggled diff for %s: %s", filename, state.expanded[filename]),
        vim.log.levels.DEBUG)
    end

    -- Re-render
    local content = generate_content()
    ui.render(state.bufnr, content)

    -- Apply ANSI highlights
    if #state.highlights > 0 then
      ansi.apply_highlights(state.bufnr, state.highlights)
    end
  end
end

-- Extract filename from a status line
local function extract_filename(line)
  return line:match("^added%s+(.+)$") or
    line:match("^modified%s+(.+)$") or
    line:match("^deleted%s+(.+)$")
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
  table.sort(line_numbers, function(a, b) return a > b end)
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
  for line_num = first_line, last_line do
    local meta = state.line_metadata[line_num]

    if config.values.debug then
      vim.notify(string.format("[RESTORE] Total metadata entries: %d", vim.tbl_count(state.line_metadata)),
        vim.log.levels.DEBUG)
      vim.notify(string.format("[RESTORE] Has diff lines: %s", has_diff_lines), vim.log.levels.DEBUG)
    end

    if meta and meta.type == "added" then
      has_diff_lines = true
      local filename = meta.filename
      if not diff_lines_to_delete[filename] then
        diff_lines_to_delete[filename] = {}
      end
      table.insert(diff_lines_to_delete[filename], meta.file_line)
    end
  end

  if config.values.debug then
    vim.notify(string.format("[DELETE] Total metadata entries: %d", vim.tbl_count(state.line_metadata)),
      vim.log.levels.DEBUG)
    vim.notify(string.format("[DELETE] Has diff lines: %s", has_diff_lines), vim.log.levels.DEBUG)
  end

  -- If we have diff lines to delete, handle partial deletion
  if has_diff_lines then
    local file_list = {}
    local total_lines = 0
    for filename, line_nums in pairs(diff_lines_to_delete) do
      table.insert(file_list, string.format("%s (%d lines)", filename, #line_nums))
      total_lines = total_lines + #line_nums
    end

    local prompt = string.format("Discard %d added line(s) from:\n  %s\n(y/n) ",
      total_lines, table.concat(file_list, "\n  "))

    vim.ui.input({ prompt = prompt }, function(input)
      if input and (input:lower() == "y" or input:lower() == "yes") then
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
    end)
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

  -- If we found files, ask for confirmation and restore them
  if #files_to_restore > 0 then
    local file_list = table.concat(files_to_restore, "\n  ")
    local prompt = string.format("Discard changes for:\n  %s\n(y/n) ", file_list)

    vim.ui.input({ prompt = prompt }, function(input)
      if input and (input:lower() == "y" or input:lower() == "yes") then
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
    end)
  else
    vim.notify("No file or diff lines found in selection", vim.log.levels.WARN)
  end
end

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

    -- Apply ANSI highlights
    if #state.highlights > 0 then
      ansi.apply_highlights(state.bufnr, state.highlights)
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

    -- Add visual mode mapping for restore
    -- Use :<C-u> to clear the range and avoid Ex mode issues
    vim.api.nvim_buf_set_keymap(
      state.bufnr,
      "v",
      "x",
      ":<C-u>lua require('neojjit').restore_visual()<CR>",
      { noremap = true, silent = true }
    )
  end

  -- Open buffer in window (full screen)
  -- Close all other windows first
  vim.cmd("only")
  ui.open_buffer(state.bufnr, {})

  -- Load and render content
  M.refresh()

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
