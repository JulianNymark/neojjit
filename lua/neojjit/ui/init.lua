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
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
  vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
  vim.api.nvim_set_option_value("filetype", opts.filetype or "neojjit", { buf = bufnr })
  vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

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
  vim.api.nvim_set_option_value("number", false, { win = winnr })
  vim.api.nvim_set_option_value("relativenumber", false, { win = winnr })
  vim.api.nvim_set_option_value("cursorline", true, { win = winnr })

  return winnr
end

-- Render content to buffer
function M.render(bufnr, lines)
  if not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end

  -- Make buffer modifiable
  vim.api.nvim_set_option_value("modifiable", true, { buf = bufnr })

  -- Set lines
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)

  -- Make buffer readonly again
  vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })

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
