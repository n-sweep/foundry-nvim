# `foundry-nvim`

![Foundry](https://wiki.factorio.com/images/Foundry_entity_anim.gif)

> WARNING: this plugin is under active development and is not intended for use by anyone

`foundry-nvim` is a plugin for editing Jupyter Notebooks inspired by predecessors such as [`molten-nvim`](https://github.com/benlubas/molten-nvim), [`magma-nvim`](https://github.com/dccsillag/magma-nvim), and [`iron.nvim`](https://github.com/Vigemus/iron.nvim)

## Installation

The plugin requires a Python environment with `jupyter-client`, `nbformat`, and `ipykernel`.

### lazy.nvim

```lua
{
    'n-sweep/foundry-nvim',
    ft = 'ipynb',
    config = function()
        require('foundry').setup({ ... })
    end,
}
```

### packer.nvim

```lua
use {
    'n-sweep/foundry-nvim',
    config = function()
        require('foundry').setup({ ... })
    end,
}
```

### vim-plug

```vim
Plug 'n-sweep/foundry-nvim'
lua require('foundry').setup({ keymap_func = func })
```

### Setup

To set your desired keymaps, pass a function with an argument `ev` to `foundry`'s `setup()` like so, ensuring your keymaps are tied only to your notebook buffer.

```lua
local func = function(ev)

    vim.keymap.set({'n', 'v'}, '<leader>fe', ":FoundryExecute<CR>", {
        desc = 'Foundry execute the current cell',
        buffer = ev.buf,
        silent = true,
    })

    vim.keymap.set(...)
end

require('foundry').setup({keymap_func = func})
```

## Usercommands

| Command                    | Description                                        |
| -------------------------- | -------------------------------------------------- |
| `FoundryExecute`           | Execute the cell under the cursor                  |
| `FoundryExecuteStep`       | Execute the cell under the cursor and step forward |
| `FoundryOpen`              | Open cell output in a floating window              |
| `FoundryDelete`            | Delete the cell under the cursor                   |
| `FoundryCreateCell`        | Create a new code cell below the current cell      |
| `FoundryCreateCellAbove`   | Create a new code cell above the current cell      |
| `FoundryCreateMdCell`      | Create a new markdown cell below the current cell  |
| `FoundryCreateMdCellAbove` | Create a new markdown cell above the current cell  |
| `FoundryNext`              | Move cursor to the next cell                       |
| `FoundryPrev`              | Move cursor to the previous cell                   |
| `FoundryStep {n}`          | Move cursor n cells (negative = backward)          |
| `FoundryShutdown`          | Shut down the kernel manager                       |
| `FoundryInfo`              | Print kernel info                                  |
