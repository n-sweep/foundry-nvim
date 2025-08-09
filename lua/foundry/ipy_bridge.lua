local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

local M = {
    handle = 0,
    on_result = function(_) logger:warn("Result handler not set") end
}


function M.setup(cell_handler, plugin_root)
    M.on_result = cell_handler.handle_ipy_message
    M.plugin_root = plugin_root

    return M
end


-- local functions -------------------------------------------------------------


local function send_to_subprocess(tbl, bufn)

    if M.handle < 1 then
        return
    end

    -- when a shutdown signal is sent from within an autocommand such as BufDelete,
    -- buffer 0 will not correctly represent the ipynb file that was closed.
    -- in this situation, we will pass it in explicitly
    bufn = bufn or vim.api.nvim_get_current_buf()

    -- add identifying information about vim
    tbl['meta'] = {
        pid = vim.fn.getpid(),
        buf = bufn,
        file = vim.api.nvim_buf_get_name(0),
    }

    local json = vim.fn.json_encode(tbl)

    vim.fn.chansend(M.handle, json .. '\n')
end


local function on_stdout(_, data, _)
    for _, line in ipairs(data) do
        if line ~= '' then
            local ok, result = pcall(vim.fn.json_decode, line)
            if ok then
                M.on_result(result)
            else
                logger:error('failed to parse:', line)
            end
        end
    end
end


local function on_stderr(chan_id, data, name)
    logger:info("ERR: " .. vim.inspect(data))
end


local function on_exit(_, code, _)

    if M.handle > 0 then
        vim.fn.jobstop(M.handle)
        M.handle = 0
        logger:info('subprocess exited')
    end
end


-- Module functions ------------------------------------------------------------


function M.start()
    if M.handle < 1 then
        M.handle = vim.fn.jobstart(
            {
                'python3', '-u',
                M.plugin_root .. '/python/main.py',
                vim.fn.getpid(),
                vim.fn.stdpath('state')  -- log file location
            },
            {
                on_stdout = on_stdout,
                on_stderr = on_stderr,
                on_exit = on_exit
            }
        )

        logger:info('ipy bridge job started: ' .. M.handle)
    end
end


function M.restart_kernel(bufn)
    send_to_subprocess({ type = 'restart' }, bufn)
end


function M.shutdown_kernel(bufn)
    send_to_subprocess({ type = 'shutdown', target = 'kernel' }, bufn)
end


function M.stop()
    send_to_subprocess({ type = 'shutdown', target = 'all' })
    M.handle = 0
end


function M.execute(input)
    local cell_id, code = input[1], input[2]
    if M.handle > 0 then
        local msg = { type = 'exec', code = code, cell_id = cell_id }
        send_to_subprocess(msg)
    else
        logger:warn('ipython not running')
        M.on_result({ type = 'execute_result', status = 'ipy_down', cell_id = cell_id })
    end
end


return M
