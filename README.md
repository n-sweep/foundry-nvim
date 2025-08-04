# Foundry

Inspired by projects like [magma-nvim](https://github.com/dccsillag/magma-nvim), [molten-nvim](https://github.com/benlubas/molten-nvim), [iron.nvim](https://github.com/Vigemus/iron.nvim), and [vim-slime](https://github.com/jpalardy/vim-slime), this plugin is specifically intended to interact with jupyter notebooks opened with [jupytext.nvim](https://github.com/GCBallesteros/jupytext.nvim) in neovim. [Molten](https://github.com/benlubas/molten-nvim) [iron](https://github.com/Vigemus/iron.nvim) makes me think of a [certain warm vacation spot](https://wiki.factorio.com/Vulcanus), thus the moniker `foundry-nvim`.

My first attempt at a similar tool is [telemux-nvim](https://github.com/n-sweep/telemux-nvim), which sends text from the open buffer to a tmux pane running an ipython repl. This worked quite well, but still had some rough edges. For one, the speed of sending lines from vim to the tmux pane by way of `tmux send-keys` was limited, resulting in a very sluggish-feeling experience when running large cells. The screen real estate taken up by requiring a split pane to show the kernel output, for another. 

More recently I've been using Molten, which uses `ipykernel` to execute code and displays the cell outputs right in the buffer, which is a much nicer experience. However it also has a few rough edges, a number of features I don't use/need, and the developer is understandably [less enthusiastic about maintaining the project into the future](https://github.com/benlubas/molten-nvim/issues/293).

## Goal

The goal is to create a plugin that executes cell contents asynchronously and displays the contents, probably in the buffer as either a floating window or virtual text. It should also manage the creation and cleanup of python kernels.

We already have custom code to define, pull content from, and move between cells from aforementioned projects. What we need:

- [x] logging
- [x] execute code (ipython)
    - [x] associate inputs with outputs (cell #s)
- [x] display the code in the buffer
- [x] automatic startup based on ipynb filetype
- [x] automatic shutdown of current kernel when buffer closes
- [x] automatic shutdown of all kernels when nvim closes
- [x] delete cell
- [x] delete all cells
- [x] delete invalid cells on edit. cells are invalid when:
    - the start line of the cell is greater than or equal to the end line
    - when a cell's separator is deleted
- [ ] output openable in a popup window


