M = {}


--- find a python virtualenv binary for the current project
--- searches the git repo root first, then recursively; falls back to system python3
--- @param venv_names string[] venv directory names to search for
--- @return string python path to the Python binary
function M.find_venv(venv_names)
    -- check environment vars first
    local env_vars = { 'VIRTUAL_ENV', 'UV_PROJECT_ENVIRONMENT', 'CONDA_PREFIX' }
    for _, var in ipairs(env_vars) do
        local env = os.getenv(var)
        if env then
            local python = env .. '/bin/python3'
            if vim.fn.executable(python) == 1 then
                return python
            end
        end
    end

    -- fall back on a venv at the root of the git repo
    local root = vim.fs.root(vim.fn.getcwd(), { '.git' }) or vim.fn.getcwd()

    for _, name in ipairs(venv_names) do
        local python = root .. '/' .. name .. '/bin/python3'
        if vim.fn.executable(python) == 1 then
            return python
        end
    end

    return 'python3'
end


local function pad(text_width, char)
    local win_width = vim.api.nvim_win_get_width(0)
    local sign_width = vim.fn.getwininfo(vim.fn.win_getid())[1].textoff
    local buf_width = win_width - sign_width - 1
    return ' ' .. string.rep(char, math.max(0, buf_width - text_width))
end


--- prepare text for virtual text display
--- @param text string|table text to be prepared; may be a string or table of strings
--- @return table
function M.prep_vtext(text, spacer, char)
    local hl_group = 'FoundryCellHL'
    char = char or " "

    if type(text) == "string" then
        local padding = pad(vim.fn.strdisplaywidth(text), char)
        return {{ text .. padding, hl_group }}
    end

    local output = {}
    for _, line in ipairs(text) do
        local padding = pad(vim.fn.strdisplaywidth(line), char)
        table.insert(output, {{ line .. padding, hl_group }})
    end

    if spacer ~= nil then
        table.insert(output, {{ ' ' }})
    end

    return output
end


--- Get the currently selected lines in visual mode.
--- @return string[] lines The selected lines
function M.get_selected_lines()
    local vstart = vim.fn.getpos("v")
    local vend = vim.fn.getpos(".")

    -- if the selection was made backward, flip start and end
    if vstart[2] > vend[2] then
        vend = vim.fn.getpos("v")
        vstart = vim.fn.getpos(".")
    end

    return vim.fn.getline(vstart[2], vend[2])
end


return M
