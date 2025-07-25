-- enable requiring from local directory
local current_file = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local plugin_dir = vim.fn.fnamemodify(current_file, ":p:h")

package.path = (
    plugin_dir .. "/lua/?.lua;" ..
    plugin_dir .. "/lua/?/init.lua;" ..
    package.path
)

local Logging, foundry, logger


local function reload()
    -- quick reloading for dev
    package.loaded['foundry'] = nil
    package.loaded['foundry.init'] = nil
    package.loaded['foundry.ipy_bridge'] = nil
    package.loaded['foundry.cell_handler'] = nil
    package.loaded['utils.logging'] = nil

    foundry = require('foundry')
    Logging = require('utils.logging')

    logger = Logging:new('logs/lua.log', 'foundry_logger')
    logger:info('Logger initialized: ' .. logger.name)
end


reload()

vim.api.nvim_create_user_command("FoundryStart", foundry.start, {})
vim.api.nvim_create_user_command("FoundryShutdown", foundry.stop, {})
vim.api.nvim_create_user_command("FoundryExecute", foundry.execute_cell, {})

-- send keys
-- ctrl + enter runs a cell
vim.keymap.set({'n', 'v'}, '<F33>', foundry.execute_cell)

-- shift + enter runs a cell and sends the cursor to the next cell
vim.keymap.set({'n', 'v'}, '<F34>', function() foundry.execute_cell() foundry.goto_next_cell() end)

-- shift + tab
vim.keymap.set('n', '<F31>', function() foundry.goto_next_cell() end)

-- alt + tab
vim.keymap.set('n', '<F32>', function() foundry.goto_prev_cell() end)
