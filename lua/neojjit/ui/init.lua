-- UI framework for neojjit
local M = {}
local config = require("neojjit.config")

-- Active buffer state
M.buffers = {}

-- Create a new buffer
function M.create_buffer(name, opts)
  opts = opts or {}

  local bufnr = vim.api.nvim_create_buf(false, true)

  -- Set buffer options
  vim.api.nvim_buf_set_option(bufnr, "buftype", "nofile")
  vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
  vim.api.nvim_buf_set_option(bufnr, "filetype", opts.filetype or "neojjit")
  vim.api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  -- Store buffer reference
  M.buffers[name] = {
    bufnr = bufnr,
    name = name,
    mappings = opts.mappings or {},
  }

  if config.values.debug then
    vim.notify(string.format("[UI] Created buffer '%s' (bufnr=%d)", name, bufnr), vim.log.levels.DEBUG)
  end

  return bufnr
end

-- Open buffer in a window
function M.open_buffer(bufnr, opts)
  opts = opts or {}

  -- Create split window
  if opts.split then
    vim.api.nvim_command(opts.split)
  end

  -- Set buffer in window
  vim.api.nvim_set_current_buf(bufnr)

  -- Set window options
  local winnr = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_option(winnr, "number", false)
  vim.api.nvim_win_set_option(winnr, "relativenumber", false)
  vim.api.nvim_win_set_option(winnr, "cursorline", true)

  return winnr
end

-- Render content to buffer
function M.render(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Make buffer modifiable
  vim.api.nvim_buf_set_option(bufnr, "modifiable", true)

  -- Set lines
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Make buffer readonly again
  vim.api.nvim_buf_set_option(bufnr, "modifiable", false)

  if config.values.debug then
    vim.notify(string.format("[UI] Rendered %d lines to buffer %d", #lines, bufnr), vim.log.levels.DEBUG)
  end
end

-- Set up keymaps for a buffer
function M.set_mappings(bufnr, mappings)
  for key, action in pairs(mappings) do
    vim.api.nvim_buf_set_keymap(
      bufnr,
      "n",
      key,
      string.format("<cmd>lua require('neojjit').%s()<CR>", action),
      { noremap = true, silent = true }
    )
  end

  if config.values.debug then
    vim.notify(string.format("[UI] Set %d mappings for buffer %d", vim.tbl_count(mappings), bufnr), vim.log.levels.DEBUG)
  end
end

-- Close a buffer
function M.close_buffer(name)
  local buf = M.buffers[name]
  if buf and vim.api.nvim_buf_is_valid(buf.bufnr) then
    vim.api.nvim_buf_delete(buf.bufnr, { force = true })
    M.buffers[name] = nil

    if config.values.debug then
      vim.notify(string.format("[UI] Closed buffer '%s'", name), vim.log.levels.DEBUG)
    end
  end
end

return M
