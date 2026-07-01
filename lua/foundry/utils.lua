M = {}


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


return M
