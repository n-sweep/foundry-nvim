vim.cmd('set rtp+=/home/n/Repos/foundry-nvim')


--- dev hot reload
function _G.reload()
    package.loaded['foundry.cell'] = nil
    package.loaded['foundry.core'] = nil
    package.loaded['foundry.ipy_bridge'] = nil
    package.loaded['foundry.logging'] = nil
    package.loaded['foundry.utils'] = nil
    dofile('/home/n/Repos/foundry-nvim/lua/foundry/init.lua')
end


------

-- create a new logger
local Logging = require('foundry.logging')
Logging:new(vim.fn.stdpath('state') .. '/foundry-nvim-lua.log', 'foundry_logger')
local logger = Logging:get_logger('foundry_logger')

local core = require('foundry.core')


--- usercommands ---------------------------------------------------------------

vim.api.nvim_create_user_command("FoundryShutdown", core.stop_ipython, {})


-- cell actions

vim.api.nvim_create_user_command("FoundryExecute", core.execute_cell_under_cursor, {})
vim.api.nvim_create_user_command("FoundryExecuteStep", function(opts)
    core.execute_cell_under_cursor()
    core.step_cells(tonumber(opts.args))
end, {})

vim.api.nvim_create_user_command("FoundryOpen", core.open_cell_floating_window, {})
vim.api.nvim_create_user_command("FoundryCreateCell", function() core.create_cell('code') end, {})
vim.api.nvim_create_user_command("FoundryCreateCellAbove", function() core.create_cell('code', true) end, {})
vim.api.nvim_create_user_command("FoundryCreateMdCell", function() core.create_cell('markdown') end, {})
vim.api.nvim_create_user_command("FoundryCreateMdCellAbove", function() core.create_cell('markdown', true) end, {})
vim.api.nvim_create_user_command("FoundryDelete", core.delete_cell_under_cursor, {})


-- navigation

vim.api.nvim_create_user_command(
    "FoundryStep",
    function(opts) core.step_cells(tonumber(opts.args)) end,
    { nargs = 1 }
)

vim.api.nvim_create_user_command("FoundryNext", "FoundryStep 1", {})
vim.api.nvim_create_user_command("FoundryPrev", "FoundryStep -1", {})


--- keymaps --------------------------------------------------------------------

local function test()
    reload()
end


local function set_keymaps(buf)

    -- F33 -> Ctrl+Enter
    vim.keymap.set({'n', 'v'}, '<F33>', ":FoundryExecute<CR>", {
        desc = 'Foundry execute the current cell',
        buffer = buf,
        silent = true,
    })

    -- F34 -> Shift+Enter
    vim.keymap.set({'n', 'v'}, '<F34>', ":FoundryExecuteStep<CR>", {
        desc = 'Foundry execute the current cell and step forward',
        buffer = buf,
        silent = true,
    })

    -- F31 -> Shift+Tab
    vim.keymap.set('n', '<F31>', ":FoundryNext<CR>", {
        desc = 'Foundry move cursor to next cell',
        buffer = 0,
        silent = true,
    })

    -- F32 -> Alt+Tab
    vim.keymap.set('n', '<F32>', ":FoundryPrev<CR>", {
        desc = 'Foundry move cursor to previous cell',
        buffer = 0,
        silent = true,
    })

    vim.keymap.set('n', '<leader>fo', ":FoundryOpen<CR>", {
        desc = 'Foundry open cell output in a temporary buffer',
        buffer = 0,
        silent = true,
    })

    vim.keymap.set({'n', 'v'}, '<leader>fr', test, {
        buffer = buf,
    })

end


--- autocommands ---------------------------------------------------------------

vim.api.nvim_create_augroup("Foundry", { clear = true })

vim.api.nvim_create_autocmd("BufReadCmd", {
    group = "Foundry",
    pattern = "*.ipynb",
    callback = function(ev)
        vim.api.nvim_buf_set_option(ev.buf, "buftype", "acwrite")
        vim.api.nvim_buf_set_option(ev.buf, "filetype", "python")
        vim.api.nvim_buf_set_name(ev.buf, ev.file)

        core.load_notebook(ev.file)
        core.start_ipython()
        set_keymaps(ev.buf)
    end,
})

vim.api.nvim_create_autocmd("BufWriteCmd", {
    group = "Foundry",
    pattern = "*.ipynb",
    callback = function(ev)
        core.save_notebook(ev.file)
        vim.bo[ev.buf].modified = false
    end,
})

local function shutdown()
    core.stop_ipython()
    vim.wait(10000, function() return core.ipython_down end, 100)
end

-- shut down kernel if buffer exits
vim.api.nvim_create_autocmd('BufDelete', {
    group = "Foundry",
    pattern = "*.ipynb",
    -- buffer must be passed in manually
    callback = shutdown
})

-- shut down ipython if vim exits
vim.api.nvim_create_autocmd('ExitPre', {
    group = "Foundry",
    pattern = "*.ipynb",
    callback = shutdown
})


--- highlight groups -----------------------------------------------------------

local hl_group = 'FoundryCellHL'
local comment = vim.api.nvim_get_hl(0, {name = 'Comment'})
local colorcol = vim.api.nvim_get_hl(0, {name = 'ColorColumn'})
vim.api.nvim_set_hl(0, hl_group, {fg = comment.fg, bg = colorcol.bg, italic = true})
