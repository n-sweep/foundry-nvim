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
local cell_handler = require('foundry.cell_handler')

-- map the ipython bridge and cell handler functions onto output module
local M = {
    execute_cell = cell_handler.execute_cell,
    goto_next_cell = cell_handler.goto_next_cell,
    goto_prev_cell = cell_handler.goto_prev_cell,
    delete_cell = cell_handler.delete_cell_under_cursor,
    delete_all_cells = cell_handler.delete_all_cells
}


function M.setup()

    -- the ipython bridge needs to know where the plugin root is
    -- to find the python main file that starts the server
    bridge.plugin_root = plugin_dir

    -- bridge & cell handler must be able to pass messages back and forth
    bridge.set_result_handler(cell_handler.handle_ipy_message)
    cell_handler.set_executor(bridge.execute)

    -- start the ipython kernel server
    bridge.start()


    -- usercommands ----------------------------------------------------------------

    vim.api.nvim_buf_create_user_command(0, "FoundryExecute", M.execute_cell, {})
    vim.api.nvim_buf_create_user_command(0, "FoundryDelete", M.delete_cell, {})
    vim.api.nvim_buf_create_user_command(0, "FoundryDeleteAll", M.delete_all_cells, {})


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

    vim.api.nvim_create_autocmd('TextChanged', {
        callback = function()
            for cell_id, _ in pairs(cell_handler.marks) do
                if not cell_handler.is_valid_cell(cell_id) then
                    cell_handler.delete_cell_by_id(cell_id)
                end
            end
        end
    })


    -- keymaps ---------------------------------------------------------------------

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
