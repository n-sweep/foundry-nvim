---@diagnostic disable: deprecated
---
local M = { handle = 0 }

local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

local current_file = debug.getinfo(1, "S").source:sub(2)
local plugin_root = vim.fs.root(current_file, {".git"})


-- local functions -------------------------------------------------------------


--- Callback for subprocess stderr - logs error output
--- @param data table Lines of error output from subprocess
local function kernel_on_stderr(_, data, _)
    for _, line in ipairs(data) do
        if line ~= '' then
            logger:error("subprocess stderr: " .. line)
        end
    end
end


--- Callback for subprocess exit - cleans up job handle
--- @param code number Exit code from subprocess
local function kernel_on_exit(_, code, _)
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


--- Sends a JSON message to the Python subprocess
--- Adds metadata (pid, buffer, file) to the message before encoding and sending
--- @param tbl table The message to send
--- @param bufn number|nil Buffer number for metadata (defaults to current buffer)
--- @return boolean success Whether the message was sent successfully
function M.send_to_subprocess(tbl, bufn)

    if M.handle < 1 then
        logger:error("No subprocess handle found")
        return false
    end

    -- when a shutdown signal is sent from within an autocommand such as BufDelete,
    -- buffer 0 will not correctly represent the ipynb file that was closed.
    -- in this situation, we will pass it in explicitly
    bufn = bufn or vim.api.nvim_get_current_buf()

    -- add identifying information about vim
    tbl.meta = {
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


--- starts a new subprocess running the python backend
--- @param args table table containing arguments
--- @param on_result function stdout message handler function
--- @return table|integer|nil result async calls return a handle (int); others return a result (table); failures return nil
function M.run_python_command(args, on_result)
    local job = {
        'python3', '-u',
        plugin_root .. '/python/main.py',
        vim.fn.getpid(),
        vim.fn.stdpath('state'),  -- log file location
        unpack(args.command)
    }

    if args.stream then
        local jobid = vim.fn.jobstart(job, {
            on_stdout = on_result,
            on_stderr = kernel_on_stderr,
            on_exit = kernel_on_exit
        })

        if jobid > 0 then
            return jobid
        else
            logger:error('failed to start python: ' .. tostring(job))
            return nil
        end
    end

    local ok, sys = pcall(vim.system, job)
    if not ok then
        logger:error('failed to start python: ' .. tostring(sys))
        return nil
    end

    local result = sys:wait()
    if result.code == 0 and result.stdout ~= '' then
        local ok, result = pcall(vim.fn.json_decode, result.stdout)
        if ok then return result end
    end

    return nil
end


return M
