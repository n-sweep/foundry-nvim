local M = {}

function M.setup()

    -- enable requiring from local directory
    local current_file = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
    local plugin_dir = vim.fn.fnamemodify(current_file, ":p:h:h:h")

    package.path = (
        plugin_dir .. "/lua/?.lua;" ..
        plugin_dir .. "/lua/?/init.lua;" ..
        package.path
    )

    -- set up a new logger
    local Logging = require('foundry.logging')
    local logger = Logging:new(vim.fn.stdpath('state') .. '/foundry-nvim-lua.log', 'foundry_logger')

    local bridge = require('foundry.ipy_bridge')
    local ch = require('foundry.cell_handler')

    -- the ipython bridge needs to know where the plugin root is
    -- to find the python main file that starts the server
    bridge.plugin_root = plugin_dir

    -- bridge & cell handler must be able to pass messages back and forth
    bridge.set_result_handler(ch.handle_ipy_message)
    ch.set_executor(bridge.execute)

    -- start the ipython kernel server
    bridge.start()


    -- expose functions to the exterior module for keymaps, etc...

    M.delete_all_cells = ch.delete_all_cells
    M.delete_cell = ch.delete_cell_under_cursor
    M.execute_cell = ch.execute_cell
    M.float_cell_output = ch.float_cell_output
    M.goto_next_cell = ch.goto_next_cell
    M.goto_prev_cell = ch.goto_prev_cell
    M.yank_cell_output = ch.yank_cell_output


    -- usercommands ----------------------------------------------------------------

    vim.api.nvim_buf_create_user_command(0, "FoundryExecute", M.execute_cell, {})
    vim.api.nvim_buf_create_user_command(0, "FoundryDelete", M.delete_cell, {})
    vim.api.nvim_buf_create_user_command(0, "FoundryDeleteAll", M.delete_all_cells, {})
    vim.api.nvim_buf_create_user_command(0, "FoundryFloatCell", M.float_cell_output, {})
    vim.api.nvim_buf_create_user_command(0, "FoundryYankCell", M.yank_cell_output, {})


    -- autocommands ----------------------------------------------------------------

    -- shut down ipython if vim exits
    vim.api.nvim_create_autocmd('ExitPre', {
        buffer = 0,
        callback = bridge.stop
    })

    -- clear cells when buffer closed
    vim.api.nvim_create_autocmd('BufDelete', {
        buffer = 0,
        callback = M.delete_all_cells
    })

    -- automatically clear virtual text around cells that have been deleted
    vim.api.nvim_create_autocmd('TextChanged', {
        buffer = 0,
        callback = function()
            for cell_id, _ in pairs(ch.marks) do
                if not ch.is_valid_cell(cell_id) then
                    ch.delete_cell_by_id(cell_id)
                end
            end
        end
    })


    -- keymaps ---------------------------------------------------------------------

    vim.keymap.set({'n', 'v'}, '<leader>fe', M.float_cell_output, { buffer = 0 })
    vim.keymap.set({'n', 'v'}, '<leader>fy', M.yank_cell_output, { buffer = 0 })

    -- send keys
    -- ctrl + enter runs a cell
    vim.keymap.set({'n', 'v'}, '<F33>', M.execute_cell, { buffer = 0 })

    -- shift + enter runs a cell and sends the cursor to the next cell
    vim.keymap.set({'n', 'v'}, '<F34>', function() M.execute_cell() M.goto_next_cell() end, { buffer = 0 })

    -- shift + tab
    vim.keymap.set('n', '<F31>', M.goto_next_cell, { buffer = 0 })

    -- alt + tab
    vim.keymap.set('n', '<F32>', M.goto_prev_cell, { buffer = 0 })

end


-- start ipython when an .ipynb file is opened
vim.api.nvim_create_autocmd('BufEnter', {
    pattern = '*.ipynb',
    callback = M.setup
})


return M
