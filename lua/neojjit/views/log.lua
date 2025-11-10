-- Log view for neojjit
local M = {}
local ui = require("neojjit.ui")
local jj = require("neojjit.commands.jj")
local config = require("neojjit.config")
local ansi = require("neojjit.ansi")

-- Current state
local state = {
  bufnr = nil,
  log_lines = {},         -- Raw log output with ANSI colors
  line_to_change_id = {}, -- Map buffer line number to change ID
  line_to_commit_id = {}, -- Map buffer line number to commit ID
  entry_lines = {},       -- List of line numbers that are log entry headers
}

-- Extract change ID and commit ID from a log line
-- Returns: change_id, commit_id, is_entry_line
local function extract_ids_from_line(line, line_index)
  -- Strip ANSI codes for parsing
  local clean_line = ansi.strip_ansi(line)

  -- Detect if this is a commit entry line by checking for graph symbols
  -- Commit lines start with:
  --   @ (working copy, ASCII)
  --   ◆ (regular commit, UTF-8: \xE2\x97\x86)
  --   ○ (open circle/commit, UTF-8: \xE2\x97\x8B)
  -- Description lines start with: │ (vertical bar, UTF-8: \xE2\x94\x82)
  -- Elided commits start with: ~ (tilde, ASCII)

  -- Check first few bytes for commit markers
  -- @ is 0x40, ◆ is UTF-8 0xE2 0x97 0x86, ○ is UTF-8 0xE2 0x97 0x8B
  local first_byte = clean_line:byte(1)
  local is_entry_line = false

  if first_byte == 0x40 then     -- '@' character
    is_entry_line = true
  elseif first_byte == 0xE2 then -- Potential UTF-8 multi-byte char
    local second_byte = clean_line:byte(2)
    local third_byte = clean_line:byte(3)
    -- ◆ (diamond) is 0xE2 0x97 0x86
    -- ○ (open circle) is 0xE2 0x97 0x8B
    if second_byte == 0x97 and (third_byte == 0x86 or third_byte == 0x8B) then
      is_entry_line = true
    end
  end

  if not is_entry_line then
    return nil, nil, false
  end

  -- Look for: graph symbol + spaces + 8-char change ID + space
  -- After @ or ◆, there are usually 2 spaces, then the 8-char change ID
  local change_id_pattern = vim.regex('\\s\\s\\(\\w\\{8}\\)\\s')
  local change_id_match = change_id_pattern:match_str(clean_line)
  local change_id = nil
  if change_id_match then
    -- Extract the captured group (8 chars after 2 spaces)
    local start_pos = change_id_match + 2 -- Skip 2 spaces
    change_id = clean_line:sub(start_pos + 1, start_pos + 8)
  end

  -- Look for commit_id (8-char hex at the end of the line)
  local commit_id_pattern = vim.regex('\\([0-9a-f]\\{8}\\)\\s*$')
  local commit_id_match = commit_id_pattern:match_str(clean_line)
  local commit_id = nil
  if commit_id_match then
    -- Extract the 8-char hex
    commit_id = clean_line:sub(commit_id_match + 1, commit_id_match + 8)
  end

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
  table.insert(lines, "Hint: j/k navigate | d describe | b set bookmark | q quit")
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

-- Set bookmark on current entry with --allow-backwards flag
function M.set_bookmark_force()
  local change_id = get_current_change_id()
  if not change_id then
    vim.notify("No change ID on current line", vim.log.levels.WARN)
    return
  end

  -- Prompt for bookmark name
  vim.ui.input({
    prompt = string.format("Set bookmark (force) on %s (default: main): ", change_id),
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

    -- Set the bookmark with force
    local result = jj.set_bookmark_force(bookmark_name, change_id)
    if result then
      -- Refresh the log view
      M.refresh()
    end
  end)
end

-- Edit (switch working copy to) current entry
function M.edit_change()
  local change_id = get_current_change_id()
  if not change_id then
    vim.notify("No change ID on current line", vim.log.levels.WARN)
    return
  end

  -- Edit the change
  local result = jj.edit(change_id)
  if result then
    -- Refresh log view to show updated state
    M.refresh()
  end
end

-- Edit (switch working copy to) current entry with --ignore-immutable flag
function M.edit_change_force()
  local change_id = get_current_change_id()
  if not change_id then
    vim.notify("No change ID on current line", vim.log.levels.WARN)
    return
  end

  -- Edit the change with force
  local result = jj.edit_force(change_id)
  if result then
    -- Refresh log view to show updated state
    M.refresh()
  end
end

-- Create new change on top of current entry
function M.new_change()
  local change_id = get_current_change_id()
  if not change_id then
    vim.notify("No change ID on current line", vim.log.levels.WARN)
    return
  end

  -- Create new change on top of this change
  local result = jj.new_on_change(change_id)
  if result then
    -- Refresh log view to show updated state
    M.refresh()
  end
end

-- Describe the change at cursor
function M.describe_change()
  local change_id = get_current_change_id()
  if not change_id then
    vim.notify("No change ID on current line", vim.log.levels.WARN)
    return
  end

  -- Describe the change with a callback to refresh log view
  jj.describe_change(change_id, function()
    M.refresh()
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
