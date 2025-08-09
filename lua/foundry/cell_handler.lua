local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

local Cell = require('foundry.cell')
local bridge = require('foundry.ipy_bridge')

local M = {
    delimiter = '# %%',
    ns = vim.api.nvim_create_namespace('foundry-nvim'),
    cells = {},
    executor = function() logger:warn('cell executor not set') end
}


-- local functions -------------------------------------------------------------


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


local function create_cell(cstart, cend)
    -- create a new cell defined by extmarks
    local cell = Cell:new(cstart, cend, M.ns, M.opts)
    logger:info('New cell created: ' .. cell.id)
    M.cells[cell.id] = cell
    return cell
end


local function get_extmark_under_cursor()
    -- look for an extmark under the cursor position

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

    local cell_id = get_extmark_under_cursor()

    if cell_id > 0 then
        return M.cells[cell_id]
    end

    -- get start of current and next cells

    -- if cstart is zero, no active cell and no valid cell pattern were found under the cursor
    local cstart = get_current_cell_separator()

    if cstart < 1 then
        return  -- skip when no cell found
    elseif cstart - get_next_cell_separator() == 1 then
        logger:info('>>>> ' .. cstart)
        logger:info('>>>> ' .. get_next_cell_separator())
        return  -- skip when cell is empty
    elseif string.find(vim.fn.getline(cstart), 'markdown') ~= nil then
        return  -- skip when markdown cell found
    end

    -- if cend is zero (last cell), replace with the end of the buffer
    local cend = get_next_cell_separator() - 1
    if cend < 1 then
        cend = vim.fn.line("$")
    end

    return create_cell(cstart, cend)
end


local function handle_execution_result(msg)
    -- handle results from ipython based on status

    local cell = M.cells[msg.cell_id]
    local exc = msg.execution_count
    local content = {}
    local status

    if msg.status == 'ok' and msg.type then
        status = 'Done'
        if msg.type == 'empty' then
            logger:info('emtpy')
        else  -- 'execution_result' and 'stream' types contain text to display
            content = vim.split(msg.text, '\n', { trimempty = true })
        end

    elseif msg.status == 'error' then
        status = 'Error'
        content = msg.result.traceback['text/plain']
        exc = 'E'
        logger:error('ipython error reported')

    elseif msg.status == 'ipy_down' then
        status = 'Error'
        content = { 'IPython Down' }
        exc = '...'

    end

    cell:update(status, exc, content)
end


-- Module functions ------------------------------------------------------------


function M.goto_next_cell()
    vim.api.nvim_win_set_cursor(0, {get_next_cell_separator(), 0})
end


function M.goto_prev_cell()
    vim.api.nvim_win_set_cursor(0, {get_prev_cell_separator(), 0})
end


function M.open_cell_floating_window()
    -- display the cell's output content in a floating window
    -- `q` or `<ESC>` to close the floating window

    local cell = get_cell_under_cursor()
    if cell == nil then return end

    local buf = vim.api.nvim_create_buf(false, true)
    local _, out_header = cell:get_headers()
    local _, row = cell:get_pos()
    local lines = cell.output_lines

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.api.nvim_open_win(buf, true, {
        relative = 'editor',
        width = vim.api.nvim_win_get_width(0),
        height = math.max(#lines, vim.api.nvim_win_get_height(0) / 2),
        row = row,
        col = 0,
        border = M.opts.border,
        title = ' ' .. out_header .. ' '
    })

    local opts = { noremap = true, silent = true }
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', '<cmd>bd!<CR>', opts)
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', '<cmd>bd!<CR>', opts)
end


function M.yank_cell_output()
    -- add the cell's output content to yank registers & system clipboard

    local cell = get_cell_under_cursor()
    if cell == nil then return end

    local output = {}
    for i = 2, #cell.output_lines do
        table.insert(output, cell.output_lines[i])
    end

    local text = table.concat(output, '\n')
    for _, reg in ipairs({'"', '0', '+'}) do
        vim.fn.setreg(reg, text)
    end
end


function M.yank_cell_input()
    -- add the cell's input content to yank registers & system clipboard

    local cell = get_cell_under_cursor()
    if cell == nil then return end

    for _, reg in ipairs({'"', '0', '+'}) do
        vim.fn.setreg(reg, cell:get_execution_input())
    end
end


function M.prune_cells()
    -- check all cells for validity and incomplete deletion
    for _, cell in pairs(M.cells) do

        -- cells that are no longer valid should have their virtual text cleared
        if not cell:is_valid() then
            cell:delete()
        end

        -- cells marked as deleted should be removed from history
        if cell.status == 'deleted' then
            M.cells[cell.id] = nil
        end

    end
end


function M.delete_cell_under_cursor()
    local cell = get_cell_under_cursor()
    if cell ~= nil then
        cell:delete()
        M.cells[cell.id] = nil
    end
end


function M.delete_all_cells()
    for _, cell in pairs(M.cells) do
        cell:delete()
        M.cells[cell.id] = nil
    end
end


function M.execute_cell()
    local cell = get_cell_under_cursor()
    if cell ~= nil then
        local code = cell:get_execution_input()
        M.executor({ cell.id, code })
        cell:update('Running', '*', {})
    end
end


function M.handle_ipy_message(message)

    if message.type == 'shutdown_all' then
        logger:info('ipython shutdown complete')
        M.ipython_down = true
    else
        handle_execution_result(message)
    end

end


function M.setup(plugin_root, opts)

    M.opts = opts
    M.executor = bridge.execute
    bridge.setup(M, plugin_root)

    -- start the ipython kernel server
    bridge.start()

    return M
end


function M.restart_kernel()
    M.delete_all_cells()
    bridge.restart_kernel()
end


function M.shutdown_kernel(bufn)
    M.delete_all_cells()
    bridge.shutdown_kernel(bufn)
end


function M.shutdown_ipython()
    M.delete_all_cells()
    bridge.stop()
end


return M
