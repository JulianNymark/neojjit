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

This project is in early development. Core functionality being implemented:

- ✅ Basic jj CLI wrapper
- ✅ Status parsing
- ✅ Repository detection
- 🚧 Status buffer UI (working copy view)
- 🚧 Basic operations (describe, new, squash)
- ⏳ Bookmark management
- ⏳ Log view
- ⏳ Diff view

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
  -- Path to jj executable (defaults to "jj")
  jj_executable = "jj",
  
  -- Enable debug logging to :messages (defaults to false)
  debug = false,
  
  -- All other options same as neogit
  kind = "tab",
  disable_hint = false,
  -- ... see neogit docs for full options
}
```

## Contributing

This is an experimental project. Contributions welcome! The goal is to provide a magit-like experience for Jujutsu users.

## Acknowledgments

- [Neogit](https://github.com/NeogitOrg/neogit) - The original project this is based on
- [Magit](https://magit.vc/) - The inspiration for the interface
- [Jujutsu](https://jj-vcs.github.io/jj/) - The version control system

## License

MIT
