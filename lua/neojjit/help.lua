-- Help popup for neojjit
local M = {}

local help_bufnr = nil
local help_winnr = nil

-- Help sections - each entry is a command description
local help_sections = {
	commands = {
		"d Describe",
		"n New change",
		"c Commit (d + n)",
		"l Log (TBD)",
		"p Pull",
		"P Push",
	},
	manipulate_changes = {
		"x Discard",
		"s squash (TBD)",
		"S Split (TBD)",
	},
	essential = {
		"<C-r> Refresh",
		"<Tab> Toggle diff",
		"<CR> Go to file",
		"? Help",
		"q Quit",
	},
}

-- Build help content from sections
local function build_help_lines()
	local commands = help_sections.commands
	local manipulate = help_sections.manipulate_changes
	local essential = help_sections.essential

	-- Find the maximum number of rows needed
	local max_rows = math.max(#commands, #manipulate, #essential)

	-- Build header
	local lines = {
		string.format(" %-22s %-23s Essential commands      ", "Commands", "Manipulate changes"),
	}

	-- Build rows
	for i = 1, max_rows do
		local col1 = commands[i] or ""
		local col2 = manipulate[i] or ""
		local col3 = essential[i] or ""

		local line = string.format(" %-22s %-23s %-24s", col1, col2, col3)
		table.insert(lines, line)
	end

	return lines
end

-- Close help popup
function M.close()
	if help_winnr and vim.api.nvim_win_is_valid(help_winnr) then
		vim.api.nvim_win_close(help_winnr, true)
		help_winnr = nil
	end
	if help_bufnr and vim.api.nvim_buf_is_valid(help_bufnr) then
		vim.api.nvim_buf_delete(help_bufnr, { force = true })
		help_bufnr = nil
	end
end

-- Show help popup
function M.show()
	-- Close existing help if open
	if help_winnr and vim.api.nvim_win_is_valid(help_winnr) then
		M.close()
		return
	end

	-- Create help content
	local lines = build_help_lines()

	-- Create buffer
	help_bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_lines(help_bufnr, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(help_bufnr, "modifiable", false)
	vim.api.nvim_buf_set_option(help_bufnr, "buftype", "nofile")

	-- Calculate window dimensions
	local width = vim.o.columns
	local height = #lines + 2 -- +2 for borders
	local row = vim.o.lines - vim.o.cmdheight - (vim.o.laststatus > 0 and 1 or 0)

	-- Create floating window at bottom
	help_winnr = vim.api.nvim_open_win(help_bufnr, true, {
		relative = "editor",
		width = width,
		height = height,
		col = 0,
		row = row,
		style = "minimal",
		border = { "─", "─", "─", "", "", "", "", "" },
		title = " Neojjit Help ",
		title_pos = "center",
		focusable = true,
	})

	-- Set window options
	vim.api.nvim_win_set_option(help_winnr, "cursorline", false)
	vim.api.nvim_win_set_option(help_winnr, "number", false)
	vim.api.nvim_win_set_option(help_winnr, "relativenumber", false)

	-- Set keymaps to close help
	local opts = { buffer = help_bufnr, noremap = true, silent = true }
	vim.keymap.set("n", "q", function()
		M.close()
	end, opts)
	vim.keymap.set("n", "<Esc>", function()
		M.close()
	end, opts)
	vim.keymap.set("n", "?", function()
		M.close()
	end, opts)

	-- Auto-close on focus lost
	vim.api.nvim_create_autocmd("WinLeave", {
		buffer = help_bufnr,
		once = true,
		callback = function()
			M.close()
		end,
	})
end

return M
