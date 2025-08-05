local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

local M = {
    delimiter = '# %%',
    ns = vim.api.nvim_create_namespace('foundry-nvim'),
    marks = {}
}


-- Local functions -------------------------------------------------------------


local function get_next_cell_separator()
    return vim.fn.search(M.delimiter, 'nW')
end


local function get_current_cell_separator()
    -- find cell divider above cursor
    local line = vim.fn.getline(".")
    if line:find(M.delimiter) and not line:find('markdown') then
        return vim.api.nvim_win_get_cursor(0)[1]
    else
        return vim.fn.search(M.delimiter, 'nbW')
    end
end


local function get_prev_cell_separator()
    -- move to the start of the current cell then search backward for the previous
    local current_pos = vim.api.nvim_win_get_cursor(0)
    vim.api.nvim_win_set_cursor(0, {get_current_cell_separator(), 0})
    local prev_cell_line = vim.fn.search(M.delimiter, 'nbW')
    vim.api.nvim_win_set_cursor(0, current_pos)
    return prev_cell_line
end


local function get_selected_lines()
    local vstart = vim.fn.getpos("v")
    local vend = vim.fn.getpos(".")

    -- if the selection was made backward, flip start and end
    if vstart[2] > vend[2] then
        vend = vim.fn.getpos("v")
        vstart = vim.fn.getpos(".")
    end

    return vim.fn.getline(vstart[2], vend[2])
end


local function create_cell(cstart, cend)
    -- create a new cell defined by extmarks

    -- 0-based indexing
    cstart = cstart - 1
    cend = cend - 1

    local start_mark = vim.api.nvim_buf_set_extmark(0, M.ns, cstart, 0, {
        end_row = cend,
        end_col = 0,
        end_right_gravity = true,
        virt_text = {{ 'In[...]', 'Comment' }},
        virt_text_pos = 'inline',
        -- hl_group = 'IncSearch'  -- debug
    })

    -- store relationship between cell mark and it's output display mark
    M.marks[start_mark] = vim.api.nvim_buf_set_extmark(0, M.ns, cend, 0, {
        virt_lines = {
            { { "Out[...]: On Hold", 'Comment' } }
        },
        virt_lines_above = true
    })

    logger:info('New cell created: ' .. start_mark)

    return start_mark
end


local function get_extmark_under_cursor()
    -- look for an extmark under the cursor position

    -- local row = vim.api.nvim_win_get_cursor(0)[1] - 1  -- 0-based indexing
    local row = get_current_cell_separator()
    local extmarks = vim.api.nvim_buf_get_extmarks(0, M.ns, 0, -1, { details = true })

    for _, extmark in ipairs(extmarks) do
        local id, start_row, details = extmark[1], extmark[2], extmark[4]
        if details and details.end_row then
            if row >= start_row and row <= details.end_row then
                return id
            end
        end
    end

    return 0
end


local function get_cell_under_cursor()
    -- get the extmark id of the cell under the cursor

    local cell = get_extmark_under_cursor()

    if cell > 0 then
        return cell
    end

    -- get start of current and next cells

    -- if cstart is zero, no active cell and no valid cell pattern were found under the cursor
    local cstart = get_current_cell_separator()
    if cstart < 1 then
        print("Foundry: No cell found")
    end

    -- if cend is zero (last cell), replace with the end of the buffer
    local cend = get_next_cell_separator() - 1
    if cend < 1 then
        cend = vim.fn.line("$")
    end

    return create_cell(cstart, cend)
end


local function get_cell_content(cell_id)
    -- get the content of a cell based on id

    local extmark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, cell_id, { details = true })
    local start_row, details = extmark[1], extmark[3]
    local end_row = details.end_row

    return vim.fn.getline(start_row + 2, end_row)
end


local function find_cell_display_fallback(cell_id)
    -- when reloading files with :so during development, the M.marks table is lost, losing the
    -- relationship between a cell extmark and it's display extmark. when this happens,
    -- `output_mark_id` is nil. in this case we search for the associate cell by location.
    -- this should not happen in production (???)

    logger:warn('cell ' .. cell_id .. ' display not found; using fallback fuction')

    -- get cell's mark
    local cell_mark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, cell_id, { details = true })
    local end_row = cell_mark[3].end_row

    -- get all extmarks
    local extmarks = vim.api.nvim_buf_get_extmarks(0, M.ns, 0, -1, { details = true })

    -- find the mark which has a start location matching the end location of the given cell
    for _, extmark in ipairs(extmarks) do
        local id, start_row = extmark[1], extmark[2]
        if start_row == end_row then
            M.marks[cell_id] = id
            return id
        end
    end
end


local function update_cell_output(cell_id, lines, input_text)
    -- given a cell id and some text, update that cell's display with the given text
    -- `input_text` is virtual text used as an input marker, eg `In[1]`

    if input_text ~= nil then
        local extmark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, cell_id, { details = true })
        local row, details = extmark[1], extmark[3]

        vim.api.nvim_buf_set_extmark(0, M.ns, row, 0, {
            id = cell_id,
            end_row = details.end_row,
            end_col = 0,
            end_right_gravity = true,
            virt_text = {{ input_text .. ' ', 'Comment' }},
            virt_text_pos = 'inline',
        })

    end

    local output_mark_id = M.marks[cell_id]

    if output_mark_id == nil then
        output_mark_id = find_cell_display_fallback(cell_id)
    end

    local extmark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, output_mark_id, {})
    local row = extmark[1]
    local output_lines = {}

    for _, line in ipairs(lines) do
        table.insert(output_lines, { { line, 'Comment' } })
    end

    vim.api.nvim_buf_set_extmark(0, M.ns, row, 0, {
        id = output_mark_id,
        virt_lines = output_lines,
        virt_lines_above = true
    })

end


-- Module functions ------------------------------------------------------------


function M.executor(_)
    -- set at runtime by foundry.init.setup()
    logger:warn('cell executor not set')
end


function M.set_executor(func)
    M.executor = func
end


function M.goto_next_cell()
    vim.api.nvim_win_set_cursor(0, {get_next_cell_separator(), 0})
end


function M.goto_prev_cell()
    vim.api.nvim_win_set_cursor(0, {get_prev_cell_separator(), 0})
end


function M.delete_cell_by_id(cell_id)
    -- delete a cell's extmark and it's output extmark
    local cell_output_id = M.marks[cell_id]

    vim.api.nvim_buf_del_extmark(0, M.ns, cell_id)
    vim.api.nvim_buf_del_extmark(0, M.ns, cell_output_id)

    M.marks[cell_id] = nil
end


function M.delete_cell_under_cursor()
    local cell_id = get_cell_under_cursor()
    M.delete_cell_by_id(cell_id)
end


function M.delete_all_cells()
    for cell_id, _ in pairs(M.marks) do
        M.delete_cell_by_id(cell_id)
    end
end


function M.is_valid_cell(cell_id)
    -- cells whose headers or content have been deleted are considered invalid

    local extmark = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, cell_id, { details = true })
    local start_row, details = extmark[1], extmark[3]

    if start_row >= details.end_row then
        return false
    elseif string.find(vim.fn.getline(start_row + 1), "^# %%") == nil then
        return false
    end

    return true
end


function M.get_execution_input()
    -- get the content of the cell under the cursor for execution

    local input
    local cell_id = get_cell_under_cursor()

    -- prioritize selections first
    local mode = vim.api.nvim_get_mode()['mode']
    if mode == 'v' or mode == 'V' or mode == '^V' then
        input = get_selected_lines()
        -- exit select mode
        vim.api.nvim_input('<Esc>')
    else
        input = get_cell_content(cell_id)
    end

    -- join lines together and strip whitespace
    local code = table.concat(input, '\n'):match("^%s*(.-)%s*$")

    return { cell_id, code }
end


function M.execute_cell()
    local input = M.get_execution_input()
    local cell_id = input[1]
    update_cell_output(cell_id, { "Out[*]: Running" }, 'In[*]')
    M.executor(input)
end


function M.handle_execution_result(result)
    -- handle results from ipython based on status

    local content, status
    local exc = result.execution_count

    if result.status == 'ok' then
        status = 'Done'
        if result.type == 'execute_result' then
            content = vim.split(result.output.data['text/plain'], '\n', { trimempty = true })
        elseif result.type == 'stream' then
            content = vim.split(result.output, '\n', { trimempty = true })
        elseif result.type == 'empty' then
            logger:info('emtpy')
        end

    elseif result.status == 'error' then
        status = 'Error'
        content = result.output.traceback['text/plain']
        logger:error('ipython error reported')

    elseif result.status == 'ipy_down' then
        status = 'Error'
        content = { 'IPython Down' }
        exc = '...'

    end

    local header =  "Out[" .. exc .. "]: " .. status
    local lines = { header }

    if content ~= nil then
        for _, line in ipairs(content) do
            table.insert(lines, line)
        end
    end

    update_cell_output(result.cell_id, lines, "In[" .. exc .. "]")
end


function M.handle_ipy_message(message)

    if message.type == 'shutdown' then
        logger:info('ipython shutdown complete')
    else
        M.handle_execution_result(message)
    end

end


function M.yank_cell_output()
    -- add the cell's output content to yank registers & system clipboard

    local output_cell_id = M.marks[get_extmark_under_cursor()]
    local ext = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, output_cell_id, { details = true })
    local vlines = ext[3].virt_lines
    local lines = {}

    for i = 2, #vlines do
        table.insert(lines, vlines[i][1][1])
    end

    local text = table.concat(lines, '\n')

    for _, reg in ipairs({'"', '0', '+'}) do
        vim.fn.setreg(reg, text)
    end
end


function M.float_cell_output()
    -- display the cell's output content in a floating window
    -- `q` or `<ESC>` to close the floating window

    local output_cell_id = M.marks[get_extmark_under_cursor()]
    local ext = vim.api.nvim_buf_get_extmark_by_id(0, M.ns, output_cell_id, { details = true })
    local row, details = ext[1], ext[3]
    local buf = vim.api.nvim_create_buf(false, true)
    local lines = {}

    for _, line in ipairs(details.virt_lines) do
        table.insert(lines, line[1][1])
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = vim.api.nvim_win_get_width(0),
        height = #lines,
        row = row,
        col = 0,
    })

    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>bd!<CR>', opts)
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>bd!<CR>', opts)
end


return M
