local api = vim.api

api.nvim_create_user_command("Neojjit", function(o)
  local neojjit = require("neojjit")
  neojjit.open(require("neojjit.lib.util").parse_command_args(o.fargs))
end, {
  nargs = "*",
  desc = "Open Neojjit",
  complete = function(arglead)
    local neojjit = require("neojjit")
    return neojjit.complete(arglead)
  end,
})

api.nvim_create_user_command("NeojjitResetState", function()
  require("neojjit.lib.state")._reset()
end, { nargs = "*", desc = "Reset any saved flags" })

api.nvim_create_user_command("NeojjitLogCurrent", function(args)
  local action = require("neojjit").action
  local path = vim.fn.expand(args.fargs[1] or "%")

  if args.range > 0 then
    action("log", "log_current", { "-L" .. args.line1 .. "," .. args.line2 .. ":" .. path })()
  else
    action("log", "log_current", { "--", path })()
  end
end, {
  nargs = "?",
  desc = "Open jj log (current) for specified file, or current file if unspecified. Optionally accepts a range.",
  range = "%",
  complete = "file",
})

api.nvim_create_user_command("NeojjitCommit", function(args)
  local commit = args.fargs[1] or "@"
  local CommitViewBuffer = require("neojjit.buffers.commit_view")
  CommitViewBuffer.new(commit):open()
end, {
  nargs = "?",
  desc = "Open jj commit view for specified commit, or @ (working copy)",
})
