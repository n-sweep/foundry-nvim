local M = { handle = 0 }
local current_file = debug.getinfo(1, "S").source:sub(2):match("(.*/)")
local plugin_dir = vim.fn.fnamemodify(current_file, ":p:h")

local Logging = require('utils.logging')
local logger = Logging:get_logger('foundry_logger')


function M.on_result(result)
    logger:warn("Result handler not set")
end


function M.set_result_handler(func)
    M.on_result = func
end


local function send_to_subprocess(tbl)
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


local function on_stderr(_, data, _)
    for _, err in ipairs(data) do
        if err ~= '' then
            logger:error('stderr:', err)
        end
    end
end


local function on_exit(_, code, _)
    if M.handle then
        vim.fn.jobstop(M.handle)
        M.handle = 0
    end
end


function M.start()

    M.handle = vim.fn.jobstart(
        {'python3', '-u', plugin_dir .. '/../../python/main.py'},
        {
            on_stdout = on_stdout,
            on_stderr = on_stderr,
            on_exit = on_exit
        }
    )

end


function M.stop()
    send_to_subprocess({ type = 'shutdown' })
end


function M.execute(input)
    local cell_id, code = input[1], input[2]
    if M.handle > 0 then
        local msg = { type = 'exec', code = code, id = cell_id }
        send_to_subprocess(msg)
    else
        logger:warn('ipython not running')
    end
end


return M
