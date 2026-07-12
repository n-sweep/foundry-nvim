local M = {}

-- create a new logger
local Logging = require('foundry.logging')
Logging:new(vim.fn.stdpath('state') .. '/foundry-nvim-lua.log', 'foundry_logger')
local logger = Logging:get_logger('foundry_logger')

local core = require('foundry.core')
local undo_redo = require('foundry.undo_redo')


--- highlight groups -----------------------------------------------------------

local hl_group = 'FoundryCellHL'
local comment = vim.api.nvim_get_hl(0, {name = 'Comment'})
local colorcol = vim.api.nvim_get_hl(0, {name = 'ColorColumn'})
vim.api.nvim_set_hl(0, hl_group, {fg = comment.fg, bg = colorcol.bg, italic = true})


--- undo/redo keymappings ------------------------------------------------------


local function set_undo_keymaps(buf)

    -- override undo
    vim.keymap.set('n', 'u', function()
        local count = vim.v.count1
        vim.cmd('normal! ' .. count .. 'u')
        vim.schedule(function()
            for _ = 1, count do
                -- pass in core state
                undo_redo.handle_undo(core)
            end
        end)
    end, { buffer = buf, silent = true, noremap = true })

    -- override redo
    vim.keymap.set('n', '<C-r>', function()
        local count = vim.v.count1
        vim.cmd('normal! ' .. count .. '\x12')
        vim.schedule(function()
            for _ = 1, count do
                -- pass in core state
                undo_redo.handle_redo(core)
            end
        end)
    end, { buffer = buf, silent = true, noremap = true })

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

        core.start_ipython()
        core.get_kernel_info(ev.buf)
        core.load_notebook(ev.file)
        set_undo_keymaps(ev.buf)
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

-- shut down kernel if buffer exits
-- shut down ipython if vim exits
vim.api.nvim_create_autocmd({'BufDelete', 'ExitPre'}, {
    group = "Foundry",
    pattern = "*.ipynb",
    -- buffer must be passed in manually
    callback = function()
        core.stop_ipython()
        vim.wait(10000, function() return core.ipython_down end, 100)
    end
})


--- usercommands ---------------------------------------------------------------

vim.api.nvim_create_user_command("FoundryShutdown", core.stop_ipython, {})
vim.api.nvim_create_user_command("FoundryInfo", function()
    print(vim.fn.json_encode(core.info))
end, {})

vim.api.nvim_create_user_command("FoundryExecute", core.execute_cell_under_cursor, {})
vim.api.nvim_create_user_command("FoundryExecuteStep", function(opts)
    local cell = core.execute_cell_under_cursor()
    core.step_cells(tonumber(opts.args), cell)
end, {})

vim.api.nvim_create_user_command("FoundryCreateCell", function() core.create_cell('code') end, {})
vim.api.nvim_create_user_command("FoundryCreateCellAbove", function() core.create_cell('code', true) end, {})
vim.api.nvim_create_user_command("FoundryCreateMdCell", function() core.create_cell('markdown') end, {})
vim.api.nvim_create_user_command("FoundryCreateMdCellAbove", function() core.create_cell('markdown', true) end, {})
vim.api.nvim_create_user_command("FoundryOpen", core.open_cell_floating_window, {})
vim.api.nvim_create_user_command("FoundryYankOutput", core.yank_cell(true), {})
vim.api.nvim_create_user_command("FoundryYankInput", core.yank_cell(false), {})
vim.api.nvim_create_user_command("FoundryDelete", core.delete_cell_under_cursor, {})

vim.api.nvim_create_user_command(
    "FoundryStep",
    function(opts) core.step_cells(tonumber(opts.args)) end,
    { nargs = 1 }
)

vim.api.nvim_create_user_command(
    "FoundryMove",
    function(opts)
        local n = tonumber(opts.args)
        if n then core.move_cell(n) else return end
    end,
    { nargs = 1 }
)

vim.api.nvim_create_user_command("FoundryMoveUp", "FoundryMove -1", {})
vim.api.nvim_create_user_command("FoundryMoveDown", "FoundryMove 1", {})
vim.api.nvim_create_user_command("FoundryNext", "FoundryStep 1", {})
vim.api.nvim_create_user_command("FoundryPrev", "FoundryStep -1", {})


--- initialize the plugin
--- @param opts table configuration options
function M.setup(opts)
    M.opts = opts

    -- set up user keymappings when an .ipynb file is opened
    vim.api.nvim_create_autocmd('BufEnter', {
        pattern = {'*.ipynb', '*.qmd'},
        callback = function(ev) opts.keymap_func(ev) end
    })
end


return M
