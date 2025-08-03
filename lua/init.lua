-- enable requiring from local directory
local current_file = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local plugin_dir = vim.fn.fnamemodify(current_file, ":p:h")

package.path = (
    plugin_dir .. "/lua/?.lua;" ..
    plugin_dir .. "/lua/?/init.lua;" ..
    package.path
)


-- start ipython when an .ipynb file is opened
vim.api.nvim_create_autocmd('BufEnter', {
    pattern = '*.ipynb',
    callback = function()

        -- set up a new logger
        local Logging = require('foundry.logging')
        -- local logger = Logging:new(plugin_dir .. '/logs/foundry-nvim-lua.log', 'foundry_logger')
        Logging:new(vim.fn.stdpath('state') .. '/foundry-nvim-lua.log', 'foundry_logger')

        require('foundry').setup(plugin_dir)

    end
})
