# Neojjit

A [Jujutsu (jj)](https://jj-vcs.github.io/jj/) interface for [Neovim](https://neovim.io), inspired by [Neogit](https://github.com/NeogitOrg/neogit), which in turn is based on [Magit](https://magit.vc/).

## What is Jujutsu?

Jujutsu (jj) is a version control system that provides a simpler, more intuitive workflow than Git:

- **No staging area** - Changes are automatically part of the working-copy commit
- **Bookmarks instead of branches** - Named pointers without a "current" concept
- **Working copy is a commit** - Represented by `@`, with parent as `@-`
- **Change IDs** - Stable identifiers that survive rewrites
- **Conflicts can be committed** - First-class support for conflicts

## Status

- ✅ Basic jj CLI wrapper
- ✅ Status parsing and display
- ✅ Repository detection
- ✅ Status buffer UI (working copy view)
- ✅ File watcher for auto-refresh
- ✅ Inline diff viewing (with difftastic support)
- ✅ Basic operations (describe, new, commit, restore)
- ✅ Push and pull (git push/fetch)
- ✅ Log view with ANSI color support
- ✅ Bookmark management (set bookmarks on changes)
- ✅ Navigate and interact with log entries (edit, new change)
- ⏳ Advanced operations (squash, rebase)

## Installation

Using [Lazy](https://github.com/folke/lazy.nvim):

```lua
{
  "JulianNymark/neojjit",
  dependencies = {
    "nvim-lua/plenary.nvim",         -- required
    "sindrets/diffview.nvim",        -- optional - Diff integration

    -- Only one of these is needed for pickers
    "nvim-telescope/telescope.nvim", -- optional
    "ibhagwan/fzf-lua",              -- optional
    "echasnovski/mini.pick",         -- optional
  },
  config = true
}
```

## Requirements

- Neovim 0.10+
- [Jujutsu](https://jj-vcs.github.io/jj/latest/install-and-setup/) installed and in PATH

## Basic Usage

```vim
:Neojjit             " Open the status buffer
```

Or using Lua:

```lua
local neojjit = require('neojjit')

-- Open status buffer
neojjit.open()

-- Open with different window kind
neojjit.open({ kind = "split" })
```

## Common Jujutsu Workflow with Neojjit

1. **Edit files** - Make changes in your working directory
2. **View status** - `:Neojjit` to see working copy changes
3. **Describe changes** - `d` to set the commit message (runs `jj describe`)
4. **Create new change** - `n` to create a new change on top (runs `jj new`)
5. **Push to remote** - `P` to push changes (runs `jj git push`)
6. **Pull from remote** - `p` to pull changes (runs `jj git fetch`)

## Key Differences from Neogit

Since Jujutsu has a different model than Git, some features work differently:

- **No staging/unstaging** - Files are either in the working copy or not
- **Bookmarks not branches** - No "current branch" concept
- **Working copy is always a commit** - Changes are automatically committed
- **Change IDs** - Commits have stable IDs that don't change on rewrite
- **No stash needed** - Just create a new change instead

## Configuration

```lua
require('neojjit').setup {
  -- Enable debug logging to :messages (defaults to false)
  debug = false,
  
  -- Use difftastic for diffs if available (defaults to true)
  -- When enabled, neojjit will automatically configure difftastic
  -- to use the full window width via jj's --config flag.
  -- This only affects the runtime command and does not modify any config files.
  use_difftastic = true,
  
  -- Auto-close status view after operations (defaults to false)
  auto_close = false,
  
  -- Custom key mappings for status view
  mappings = {
    status = {
      ["q"] = "close",
      ["<C-r>"] = "refresh",
      ["d"] = "describe",
      ["n"] = "new",
      ["c"] = "commit",
      ["x"] = "restore",
      ["l"] = "log",
      ["?"] = "help",
      ["<CR>"] = "show_diff",
      ["<Tab>"] = "toggle",
      ["p"] = "pull",
      ["P"] = "push",
    },
  },
}
```

### Difftastic Integration

If [difftastic](https://github.com/Wilfred/difftastic) is installed and `use_difftastic` is enabled, neojjit will automatically use it for displaying diffs with the following features:

- Automatically adjusts diff width to match your current window width
- Uses syntax-aware structural diffs
- Configuration is applied per-command and never modifies your jj config files

To disable difftastic, set `use_difftastic = false` in your neojjit config.

## Contributing

This is an experimental project. Contributions welcome! The goal is to provide a magit-like experience for Jujutsu users.

## Acknowledgments

- [Neogit](https://github.com/NeogitOrg/neogit) - The original project this is based on
- [Magit](https://magit.vc/) - The inspiration for the interface
- [Jujutsu](https://jj-vcs.github.io/jj/) - The version control system

## License

MIT
