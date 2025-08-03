local Logging = require('utils.logging')
local logger = Logging:get_logger('foundry_logger')

local M = {
    handle = 0,
    plugin_root = nil,  -- set at runtime by foundry.init.setup()
}


function M.on_result(result)
    -- set at runtime by foundry.init.setup()
    logger:warn("Result handler not set")
end


function M.set_result_handler(func)
    M.on_result = func
end


local function send_to_subprocess(tbl)

    -- add identifying information about vim
    tbl['id'] = {
        pid = vim.fn.getpid(),
        buffer = vim.api.nvim_get_current_buf(),
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
    if M.handle then
        vim.fn.jobstop(M.handle)
        M.handle = 0
        logger:info('subprocess exited')
    end
end


function M.start()

    if M.handle == 0 then

        M.handle = vim.fn.jobstart(
            { 'python3', '-u', M.plugin_root .. '/python/main.py', vim.fn.stdpath('state') },
            {
                on_stdout = on_stdout,
                on_stderr = on_stderr,
                on_exit = on_exit
            }
        )

        logger:info('job started: ' .. M.handle)
    end
end


function M.stop()
    send_to_subprocess({ type = 'shutdown' })
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
