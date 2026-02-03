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


--- Sends a JSON message to the Python subprocess
--- Adds metadata (pid, buffer, file) to the message before encoding and sending
--- @param tbl table The message to send (will be modified to add 'meta' field)
--- @param bufn number|nil Buffer number for metadata (defaults to current buffer)
--- @return boolean success Whether the message was sent successfully
local function send_to_subprocess(tbl, bufn)

    if M.handle < 1 then
        logger:error("No subprocess handle found")
        return false
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
    local result = vim.fn.chansend(M.handle, json .. '\n')

    if result < 1 then
        logger:error("chansend failed: " .. json .. '\n')
        return false
    end

    return true
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

            vim.notify(
                'Foundry: Python kernel subprocess crashed (exit code: ' .. code .. ')',
                vim.log.levels.ERROR
            )

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


--- Restarts the kernel for the specified buffer
--- @param bufn number|nil Buffer number (defaults to current buffer)
--- @return boolean success Whether the restart command was sent successfully
function M.restart_kernel(bufn)
    return send_to_subprocess({ type = 'restart' }, bufn)
end


--- Shuts down the kernel for the specified buffer
--- @param bufn number|nil Buffer number (defaults to current buffer)
--- @return boolean success Whether the shutdown command was sent successfully
function M.shutdown_kernel(bufn)
    return send_to_subprocess({ type = 'shutdown', target = 'kernel' }, bufn)
end


--- Stops the entire Python subprocess and all kernels
--- Note: M.handle will be reset to 0 by the on_exit callback when subprocess terminates
--- @return boolean success Whether the shutdown command was sent successfully
function M.stop()
    return send_to_subprocess({ type = 'shutdown', target = 'all' })
end


--- Executes code in the Python kernel and sends results to the result handler
--- @param cell_id number The cell identifier
--- @param code string The Python code to execute
function M.execute(cell_id, code)
    if M.handle > 0 then

        local msg = { type = 'exec', code = code, cell_id = cell_id }
        local success = send_to_subprocess(msg)

        if not success then
            -- Send failed - notify cell with error
            M.on_result({
                cell_id = cell_id,
                status = 'error',
                execution_count = 'E',
                messages = {
                    {output_type = 'error', text = 'Failed to send execution request'}
                }
            })
        end

    else

        -- Subprocess not running
        M.on_result({
            cell_id = cell_id,
            status = 'error',
            execution_count = 'E',
            messages = {
                {output_type = 'error', text = 'IPython subprocess not running'}
            }
        })

    end
end


return M
