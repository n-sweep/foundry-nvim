local M = {}


function M.setup(opts)

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
    Logging:new(vim.fn.stdpath('state') .. '/foundry-nvim-lua.log', 'foundry_logger')

    local ch = require('foundry.cell_handler').setup(plugin_dir, {
        display_max_lines = 16,
        border = 'rounded'
    })


    -- user functions --------------------------------------------------------------

    -- expose functions to the exterior module for keymaps, etc...
    M.delete_all_cells      = ch.delete_all_cells
    M.delete_cell           = ch.delete_cell_under_cursor
    M.execute_cell          = ch.execute_cell
    M.goto_next_cell        = ch.goto_next_cell
    M.goto_prev_cell        = ch.goto_prev_cell
    M.open_cell             = ch.open_cell_floating_window
    M.restart_kernel        = ch.restart_kernel
    M.yank_cell_input       = ch.yank_cell_input
    M.yank_cell_output      = ch.yank_cell_output


    -- usercommands ----------------------------------------------------------------

    vim.api.nvim_create_user_command("FoundryExecute", M.execute_cell, {})
    vim.api.nvim_create_user_command("FoundryOpenCell", M.open_cell, {})

    vim.api.nvim_create_user_command("FoundryDelete", M.delete_cell, {})
    vim.api.nvim_create_user_command("FoundryDeleteAll", M.delete_all_cells, {})

    vim.api.nvim_create_user_command("FoundryYankCellOutput", M.yank_cell_output, {})
    vim.api.nvim_create_user_command("FoundryYankCellInput", M.yank_cell_input, {})

    vim.api.nvim_create_user_command("FoundryRestart", M.restart_kernel, {})


    -- autocommands ----------------------------------------------------------------

    -- shut down kernel if buffer exits
    vim.api.nvim_create_autocmd('BufUnload', {
        buffer = 0,
        -- buffer must be passed in manually
        callback = function(args) ch.shutdown_kernel(args.buf) end
    })

    -- shut down ipython if vim exits
    vim.api.nvim_create_autocmd('ExitPre', {
        buffer = 0,
        callback = function()
            ch.shutdown_ipython()
            vim.wait(10000, function() return ch.ipython_down end, 100)
        end
    })

    -- automatically clear virtual text around cells that have been deleted
    vim.api.nvim_create_autocmd('TextChanged', {
        buffer = 0,
        callback = ch.prune_cells
    })

end


return M
