-- ANSI color code parser for neojjit
-- Converts ANSI escape sequences to Neovim highlight groups
local M = {}

-- ANSI color code to highlight group mapping (for standard codes)
local color_map = {
  -- Standard colors (30-37 foreground, 40-47 background)
  ["30"] = "Black",
  ["31"] = "Red",
  ["32"] = "Green",
  ["33"] = "Yellow",
  ["34"] = "Blue",
  ["35"] = "Magenta",
  ["36"] = "Cyan",
  ["37"] = "White",

  -- Bright colors (90-97 foreground)
  ["90"] = "DarkGray",
  ["91"] = "Red",
  ["92"] = "Green",
  ["93"] = "Yellow",
  ["94"] = "Blue",
  ["95"] = "Magenta",
  ["96"] = "Cyan",
  ["97"] = "White",

  -- Default colors
  ["39"] = nil, -- Default foreground (reset to default)
  ["49"] = nil, -- Default background (reset to default)
}

-- ANSI 256 color palette (subset - most commonly used by jj)
local color_256_map = {
  -- 256 color palette (0-15) - brightened palette
  ["0"] = "#3a3a3a",
  ["1"] = "#ff6b6b",
  ["2"] = "#51cf66",
  ["3"] = "#ffd43b",
  ["4"] = "#5c7cfa",
  ["5"] = "#e599f7",
  ["6"] = "#3bc9db",
  ["7"] = "#e9ecef",
  ["8"] = "#adb5bd",
  ["9"] = "#ff8787",
  ["10"] = "#69db7c",
  ["11"] = "#ffe066",
  ["12"] = "#748ffc",
  ["13"] = "#f388ff",
  ["14"] = "#66d9e8",
  ["15"] = "#ffffff",
}

-- Get highlight group name for 256 color
local function get_color_256_hl(color_num, bold)
  local hl_name = "NeojjitColor" .. color_num .. (bold and "Bold" or "")

  -- Create highlight group if it doesn't exist
  if not vim.api.nvim_get_hl(0, { name = hl_name }).fg then
    local color = color_256_map[color_num]
    if color then
      vim.api.nvim_set_hl(0, hl_name, { fg = color, bold = bold or false })
    end
  end

  return hl_name
end

-- Parse ANSI escape sequences and return clean text with highlight regions
-- Returns: { text = "cleaned text", highlights = {{line, col_start, col_end, group}...} }
function M.parse_line(line, line_num)
  local highlights = {}
  local clean_text = ""
  local col = 0
  local current_color = nil
  local color_start_col = nil
  local bold = false

  -- Pattern to match ANSI escape sequences
  -- ESC[...m format where ESC is \27 or \x1b
  local pos = 1
  while pos <= #line do
    -- Look for ANSI escape sequence
    local esc_start, esc_end, codes = line:find("\27%[([%d;]*)m", pos)

    if not esc_start then
      -- No more escape sequences, add rest of line
      local rest = line:sub(pos)
      clean_text = clean_text .. rest

      -- If we had an active color, finish its region
      if current_color and color_start_col then
        table.insert(highlights, {
          line = line_num,
          col_start = color_start_col,
          col_end = col + #rest,
          group = current_color,
        })
      end
      break
    end

    -- Add text before escape sequence
    local text_before = line:sub(pos, esc_start - 1)
    if #text_before > 0 then
      clean_text = clean_text .. text_before
      col = col + #text_before
    end

    -- If we had an active color, finish its region
    if current_color and color_start_col and #text_before > 0 then
      table.insert(highlights, {
        line = line_num,
        col_start = color_start_col,
        col_end = col,
        group = current_color,
      })
    end

    -- Parse the color codes
    if codes == "" or codes == "0" then
      -- Reset/normal
      current_color = nil
      color_start_col = nil
      bold = false
    else
      -- Parse color codes - handle both standard and 256 color modes
      local codes_table = {}
      for code in codes:gmatch("%d+") do
        table.insert(codes_table, code)
      end

      local i = 1
      local temp_color = nil

      while i <= #codes_table do
        local code = codes_table[i]

        if code == "0" then
          -- Reset
          current_color = nil
          color_start_col = nil
          bold = false
          temp_color = nil
        elseif code == "1" then
          -- Bold/bright
          bold = true
        elseif code == "2" then
          -- Dim - ignore for now
        elseif code == "22" then
          -- Not bold
          bold = false
        elseif code == "38" and codes_table[i + 1] == "5" and codes_table[i + 2] then
          -- 256-color mode: 38;5;N (for log view colors)
          local color_num = codes_table[i + 2]
          current_color = get_color_256_hl(color_num, bold)
          color_start_col = col
          i = i + 2 -- Skip the next two codes (5 and N)
        elseif code == "39" or code == "49" then
          -- Reset to default foreground/background
          current_color = nil
          color_start_col = nil
          temp_color = nil
        else
          -- Check for standard ANSI color codes (30-37, 90-97)
          local color_name = color_map[code]
          if color_name then
            temp_color = color_name
          end
        end

        i = i + 1
      end

      -- Apply the standard color if we found one (for difftastic in status view)
      if temp_color then
        current_color = "Neojjit" .. temp_color .. (bold and "Bold" or "")
        color_start_col = col
      end
    end

    pos = esc_end + 1
  end

  return clean_text, highlights
end

-- Parse multiple lines and return cleaned lines with all highlights
function M.parse_lines(lines, start_line_num)
  start_line_num = start_line_num or 0

  local cleaned_lines = {}
  local all_highlights = {}

  for i, line in ipairs(lines) do
    local clean_text, highlights = M.parse_line(line, start_line_num + i - 1)
    table.insert(cleaned_lines, clean_text)

    for _, hl in ipairs(highlights) do
      table.insert(all_highlights, hl)
    end
  end

  return cleaned_lines, all_highlights
end

-- Apply highlights to a buffer
function M.apply_highlights(bufnr, highlights, namespace)
  namespace = namespace or vim.api.nvim_create_namespace("neojjit_ansi")

  -- Clear existing highlights in this namespace
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)

  for _, hl in ipairs(highlights) do
    -- nvim_buf_add_highlight uses 0-based line numbers and byte-indexed columns
    pcall(vim.api.nvim_buf_add_highlight, bufnr, namespace, hl.group, hl.line, hl.col_start, hl.col_end)
  end
end

-- Strip ANSI escape sequences from a string
function M.strip_ansi(str)
  if not str then
    return ""
  end
  -- Remove ANSI escape sequences (ESC[...m format)
  return str:gsub("\27%[[%d;]*m", "")
end

-- Define highlight groups for ANSI colors
function M.setup_highlight_groups()
  -- Define highlight groups that map to terminal colors
  vim.api.nvim_set_hl(0, "NeojjitBlack", { fg = "#000000" })
  vim.api.nvim_set_hl(0, "NeojjitRed", { fg = "#ff5555" })
  vim.api.nvim_set_hl(0, "NeojjitGreen", { fg = "#50fa7b" })
  vim.api.nvim_set_hl(0, "NeojjitYellow", { fg = "#f1fa8c" })
  vim.api.nvim_set_hl(0, "NeojjitBlue", { fg = "#bd93f9" })
  vim.api.nvim_set_hl(0, "NeojjitMagenta", { fg = "#ff79c6" })
  vim.api.nvim_set_hl(0, "NeojjitCyan", { fg = "#8be9fd" })
  vim.api.nvim_set_hl(0, "NeojjitWhite", { fg = "#f8f8f2" })
  vim.api.nvim_set_hl(0, "NeojjitDarkGray", { fg = "#6272a4" })

  -- Bold variants (brighter versions)
  vim.api.nvim_set_hl(0, "NeojjitBlackBold", { fg = "#000000", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitRedBold", { fg = "#ff5555", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitGreenBold", { fg = "#50fa7b", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitYellowBold", { fg = "#f1fa8c", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitBlueBold", { fg = "#bd93f9", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitMagentaBold", { fg = "#ff79c6", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitCyanBold", { fg = "#8be9fd", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitWhiteBold", { fg = "#f8f8f2", bold = true })
  vim.api.nvim_set_hl(0, "NeojjitDarkGrayBold", { fg = "#6272a4", bold = true })
end

return M
