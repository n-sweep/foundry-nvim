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
        file = vim.api.nvim_buf_get_name(bufn),
    }

    local json = vim.fn.json_encode(tbl)

    vim.fn.chansend(M.handle, json .. '\n')
end


--- Callback for subprocess stdout - parses JSON messages and routes to result handler
--- @param data table Lines of output from subprocess
local function on_stdout(_, data, _)
    for _, line in ipairs(data) do
        if line ~= '' then
            local ok, result = pcall(vim.fn.json_decode, line)
            if ok then
                M.on_result(result)
            else
                logger:error('failed to parse: ' .. line)
            end
        end
    end
end


--- Callback for subprocess stderr - logs error output
--- @param data table Lines of error output from subprocess
local function on_stderr(_, data, _)
    for _, line in ipairs(data) do
        if line ~= '' then
            logger:error("subprocess stderr: " .. line)
        end
    end
end


--- Callback for subprocess exit - cleans up job handle
--- @param code number Exit code from subprocess
local function on_exit(_, code, _)
    if M.handle > 0 then
        M.handle = 0
        if code == 0 then
            logger:info('subprocess exited cleanly')
        else
            logger:error('subprocess exited with code: ' .. code)
        end
    end
end


-- Module functions ------------------------------------------------------------


--- starts a new subprocess running the python kernel manager
--- @return boolean success boolean indicating whether the subprocess started successfully
function M.start()
    if M.handle < 1 then
        local jobid = vim.fn.jobstart(
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

        if jobid > 0 then
            logger:info('ipy bridge job started: ' .. jobid)
            M.handle = jobid
            return true
        end

        logger:error('failed to start python subprocess: ' .. jobid)
    end
    return false
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
