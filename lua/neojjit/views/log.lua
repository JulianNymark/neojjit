-- Log view for neojjit
local M = {}
local ui = require("neojjit.ui")
local jj = require("neojjit.commands.jj")
local config = require("neojjit.config")
local ansi = require("neojjit.ansi")

-- Current state
local state = {
  bufnr = nil,
  log_lines = {}, -- Raw log output with ANSI colors
  line_to_change_id = {}, -- Map buffer line number to change ID
  line_to_commit_id = {}, -- Map buffer line number to commit ID
  entry_lines = {}, -- List of line numbers that are log entry headers
}

-- Extract change ID and commit ID from a log line
-- Returns: change_id, commit_id, is_entry_line
local function extract_ids_from_line(line, line_index)
  -- Strip ANSI codes for parsing
  local clean_line = ansi.strip_ansi(line)

  -- Log entries alternate: line 1 is commit, line 2 is description, line 3 is commit, etc.
  -- So odd-numbered lines (1, 3, 5, ...) are commit entries
  local is_entry_line = (line_index % 2) == 1

  if not is_entry_line then
    return nil, nil, false
  end

  -- Look for: any leading chars + 2 spaces + 8-char change ID + space
  -- The ^.-  matches any characters non-greedily (handles UTF-8 symbols)
  local change_id = clean_line:match("^.-%s%s(%w%w%w%w%w%w%w%w)%s")

  -- Look for commit_id (8-char hex at the end of the line)
  local commit_id = clean_line:match("([%da-f]%w%w%w%w%w%w%w)%s*$")

  return change_id, commit_id, true
end

-- Generate buffer content from log lines
local function generate_content()
  local lines = {}
  local all_highlights = {}
  state.line_to_change_id = {}
  state.line_to_commit_id = {}
  state.entry_lines = {}

  -- Header (no ANSI codes in header)
  table.insert(lines, "Log View")
  table.insert(lines, "Hint: j/k navigate | b set bookmark | q quit ")
  table.insert(lines, "")

  if #state.log_lines == 0 then
    table.insert(lines, "  (no log entries)")
    return lines, all_highlights
  end

  -- Add log entries with ANSI coloring
  for log_line_index, log_line in ipairs(state.log_lines) do
    local line_num = #lines -- Current line index (0-based for highlights)

    -- Parse ANSI codes and get clean text with highlights
    local clean_text, highlights = ansi.parse_line(log_line, line_num)
    table.insert(lines, clean_text)

    -- Collect highlights
    for _, hl in ipairs(highlights) do
      table.insert(all_highlights, hl)
    end

    -- Extract and store IDs for this line (use original log_line with ANSI)
    local change_id, commit_id, is_entry_line = extract_ids_from_line(log_line, log_line_index)
    -- Line number is now 1-based for our mapping (lua convention)
    local mapping_line_num = line_num + 1
    if change_id then
      state.line_to_change_id[mapping_line_num] = change_id
    end
    if commit_id then
      state.line_to_commit_id[mapping_line_num] = commit_id
    end
    -- Only mark as entry line if explicitly detected as one
    if is_entry_line then
      table.insert(state.entry_lines, mapping_line_num)
    end
  end

  return lines, all_highlights
end

-- Get change ID for current line
local function get_current_change_id()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return nil
  end

  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  return state.line_to_change_id[line_num]
end

-- Get commit ID for current line
local function get_current_commit_id()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return nil
  end

  local line_num = vim.api.nvim_win_get_cursor(0)[1]
  return state.line_to_commit_id[line_num]
end

-- Navigate to next log entry
function M.next_entry()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Find next entry line after current position
  for _, entry_line in ipairs(state.entry_lines) do
    if entry_line > current_line then
      vim.api.nvim_win_set_cursor(0, { entry_line, 0 })
      return
    end
  end

  -- If no next entry, stay at current position or go to last entry
  if #state.entry_lines > 0 then
    vim.api.nvim_win_set_cursor(0, { state.entry_lines[#state.entry_lines], 0 })
  end
end

-- Navigate to previous log entry
function M.prev_entry()
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    return
  end

  local current_line = vim.api.nvim_win_get_cursor(0)[1]

  -- Find previous entry line before current position
  for i = #state.entry_lines, 1, -1 do
    if state.entry_lines[i] < current_line then
      vim.api.nvim_win_set_cursor(0, { state.entry_lines[i], 0 })
      return
    end
  end

  -- If no previous entry, stay at current position or go to first entry
  if #state.entry_lines > 0 then
    vim.api.nvim_win_set_cursor(0, { state.entry_lines[1], 0 })
  end
end

-- Copy change ID to clipboard
function M.copy_change_id()
  local change_id = get_current_change_id()
  if change_id then
    vim.fn.setreg("+", change_id)
    vim.notify(string.format("Copied change ID: %s", change_id), vim.log.levels.INFO)
  else
    vim.notify("No change ID on current line", vim.log.levels.WARN)
  end
end

-- Copy commit hash to clipboard
function M.copy_commit_hash()
  local commit_id = get_current_commit_id()
  if commit_id then
    vim.fn.setreg("+", commit_id)
    vim.notify(string.format("Copied commit hash: %s", commit_id), vim.log.levels.INFO)
  else
    vim.notify("No commit ID on current line", vim.log.levels.WARN)
  end
end

-- Set bookmark on current entry
function M.set_bookmark()
  local change_id = get_current_change_id()
  if not change_id then
    vim.notify("No change ID on current line", vim.log.levels.WARN)
    return
  end

  -- Prompt for bookmark name
  vim.ui.input({
    prompt = string.format("Set bookmark on %s (default: main): ", change_id),
  }, function(input)
    -- User cancelled
    if input == nil then
      vim.notify("Cancelled", vim.log.levels.INFO)
      return
    end

    -- Use default if empty
    local bookmark_name = input
    if bookmark_name == "" then
      bookmark_name = "main"
    end

    -- Set the bookmark
    local result = jj.set_bookmark(bookmark_name, change_id)
    if result then
      -- Refresh the log view
      M.refresh()
    end
  end)
end

-- Refresh log view
function M.refresh()
  if config.values.debug then
    vim.notify("[LOG] Refreshing log", vim.log.levels.DEBUG)
  end

  -- Get log entries
  local log_lines = jj.log()
  if log_lines then
    state.log_lines = log_lines
  end

  -- Re-render if buffer exists
  if state.bufnr and vim.api.nvim_buf_is_valid(state.bufnr) then
    local content, highlights = generate_content()
    ui.render(state.bufnr, content)

    -- Apply ANSI color highlights with dedicated namespace for log view
    local log_namespace = vim.api.nvim_create_namespace("neojjit_log_ansi")
    ansi.apply_highlights(state.bufnr, highlights, log_namespace)
  end

  vim.notify("Log refreshed", vim.log.levels.INFO)
end

-- Open log view
function M.open()
  -- Create buffer if it doesn't exist
  if not state.bufnr or not vim.api.nvim_buf_is_valid(state.bufnr) then
    state.bufnr = ui.create_buffer("log", {
      filetype = "neojjit-log",
      mappings = config.values.mappings.log or {},
    })

    -- Set up keymaps
    local mappings = config.values.mappings.log or {}
    ui.set_mappings(state.bufnr, mappings)

    -- Add j/k navigation to jump between log entries
    vim.api.nvim_buf_set_keymap(
      state.bufnr,
      "n",
      "j",
      ":lua require('neojjit.views.log').next_entry()<CR>",
      { noremap = true, silent = true }
    )
    vim.api.nvim_buf_set_keymap(
      state.bufnr,
      "n",
      "k",
      ":lua require('neojjit.views.log').prev_entry()<CR>",
      { noremap = true, silent = true }
    )
  end

  -- Open buffer in window (full screen)
  vim.cmd("only")
  ui.open_buffer(state.bufnr, {})

  -- Load and render content
  M.refresh()
end

-- Close log view and return to status view
function M.close()
  ui.close_buffer("log")
  state.bufnr = nil

  -- Return to status view
  local status_view = require("neojjit.views.status")
  status_view.open()
end

return M
