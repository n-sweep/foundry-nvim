---@diagnostic disable: deprecated

local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')
local utils = require('foundry.utils')

local M = {
    handle = 0,
    message_handler = nil,
    plugin_root = vim.fs.root(
        debug.getinfo(1, "S").source:sub(2),
        {".git"}
    ),
    venv_names = { '.venv', 'venv', 'env' },
}

M.venv = utils.find_venv(M.venv_names)


-- local functions -------------------------------------------------------------


--- Callback for subprocess stderr - logs error output
--- @param data table Lines of error output from subprocess
local function kernel_on_stderr(_, data, _)
    for _, line in ipairs(data) do
        if line ~= '' then
            logger:error("subprocess stderr: " .. line)
            vim.notify("stderr: " .. line, vim.log.levels.ERROR)
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
        end

        logger:info('-------------------')
        logger:info(' ')
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
        venv = M.venv,
    }

    local json = vim.fn.json_encode(tbl)
    local result = vim.fn.chansend(M.handle, json .. '\n')

    if result < 1 then
        logger:error("chansend failed: " .. json .. '\n')
        return false
    end

    logger:info('kernel message sent:     ' .. tbl.type)
    return true
end


--- starts a new subprocess running the python backend
--- @param args table table containing arguments
--- @return table|nil result
function M.run_python_command(args)
    local job = {
        M.venv, '-u',
        M.plugin_root .. '/python/main.py',
        vim.fn.getpid(),
        vim.fn.stdpath('state'),  -- log file location
        unpack(args.command)
    }

    -- run streaming job
    if args.stream then
        local jobid = vim.fn.jobstart(job, {
            on_stdout = M.message_handler,
            on_stderr = kernel_on_stderr,
            on_exit = kernel_on_exit
        })

        if jobid > 0 then
            return { handle = jobid }
        else
            logger:error('failed to start python: ' .. tostring(job))
            return nil
        end
    end

    -- run non-streaming job
    local ok, sys = pcall(vim.system, job)
    if not ok then
        logger:error('failed to start python: ' .. tostring(sys))
        return nil
    end

    -- wait for job to complete
    local result = sys:wait()
    if result.code == 0 and result.stdout ~= '' then
        local ok, result = pcall(vim.fn.json_decode, result.stdout)
        if ok then return result end
    else
        logger:error('NONSTREAMING JOB FAILED - code: ' .. result.code .. ', stdout: ' .. result.stdout)
    end

    return nil
end


return M
