local M = {
    title = 'welcome to foundry-nvim',
    text = {'one two three', 'hello', 'goodbye'},
    ns = vim.api.nvim_create_namespace('foundry-nvim'),
    cells = {},
    cell_order = {}
}

local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

local Cell = require('foundry.cell')
local bridge = require('foundry.ipy_bridge')
local utils = require('foundry.utils')

local pending_msg = ''


--- buffer functions -----------------------------------------------------------


--- starts a new subprocess running the python kernel manager
--- @return nil
function M.start_ipython()
    if bridge.handle > 0 then
        logger:warn('kernel already started')
        return nil
    end

    local args = {
        command = {'kernel'},
        stream = true,
    }
    local result = bridge.run_python_command(args, M.handle_kernel_message)
    if result then
        bridge.handle = result
        logger:info('kernel started')
    else
        logger:error('kernel failed to start')
    end
end


--- Stops the entire Python subprocess and all kernels
--- Note: M.handle will be reset to 0 by the on_exit callback when subprocess terminates
--- @return boolean success Whether the shutdown command was sent successfully
--- @return nil
function M.stop_ipython()
    return bridge.send_to_subprocess({ type = 'shutdown', target = 'all' })
end


--- Restarts the kernel for the specified buffer
--- @param bufn number|nil Buffer number (defaults to current buffer)
--- @return boolean success Whether the restart command was sent successfully
function M.restart_kernel(bufn)
     return bridge.send_to_subprocess({ type = 'restart' }, bufn)
end


--- Shuts down the kernel for the specified buffer
--- @param bufn number|nil Buffer number (defaults to current buffer)
--- @return boolean success Whether the shutdown command was sent successfully
function M.shutdown_kernel(bufn)
    return bridge.send_to_subprocess({ type = 'shutdown', target = 'kernel' }, bufn)
end


--- calls to the python backend to read a jupyter notebook
--- @param file string location of the notebook to be read
--- @return nil
function M.load_notebook(file)
    local msg = { command = { 'read', file } }
    local result = bridge.run_python_command(msg, M.handle_kernel_message)
    if result then
        logger:info(file .. ' read')
        M.cells = {}
        M.cell_order = {}
        for _, data in ipairs(result.cells) do
            local cell = Cell:new(M.ns, data)
            M.cells[cell.id] = cell
            table.insert(M.cell_order, cell.id)
        end
        M.place_cells()
    else
        logger:error('failed to read notebook: ' .. file)
    end
end


--- calls to the python backend to save a jupyter notebook
--- @param file string location of the notebook to be written
--- @return nil
function M.save_notebook(file)
    local cell_data = {}

    for _, cell_id in ipairs(M.cell_order) do
        local cell = M.cells[cell_id]
        local lines = cell:get_input_from_buffer()
        cell.data.source = table.concat(lines, '\n')
        table.insert(cell_data, cell.data)
    end

    local ok, json = pcall(vim.fn.json_encode, cell_data)

    if not ok then
        logger:error('failed to encode cells')
    end

    local msg = { command = { 'write', json, file } }
    local result = bridge.run_python_command(msg, M.handle_kernel_message)

    if result then
        logger:info(file .. ' written')
    else
        logger:warn('failed to write notebook: ' .. file)
    end

end


--- Clear the buffer and place the header and cells in the buffer
--- @return nil
function M.place_cells()
    -- set the header
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'', ''})
    vim.api.nvim_buf_set_extmark(0, M.ns, 0, 0, {
        virt_text = utils.prep_vtext(M.title),
        virt_text_pos = 'overlay',
        virt_lines = utils.prep_vtext(M.text, true),
    })

    local prev_cell = nil
    for _, cell_id in ipairs(M.cell_order) do
        local cell = M.cells[cell_id]
        local row

        if prev_cell ~= nil then
            _, row = prev_cell:get_range()
        end

        cell:place_in_buffer(row)
        prev_cell = cell
    end
end


--- Callback for subprocess stdout - parses JSON messages and routes to result handler
--- @param data table Lines of output from subprocess
--- @return nil
function M.handle_kernel_message(_, data, _)
    for _, line in ipairs(data) do
        if line ~= '' then
            pending_msg = pending_msg .. line
        else
            if pending_msg ~= '' then

                local ok, result = pcall(vim.fn.json_decode, pending_msg)
                if ok then
                    logger:info('kernel message received')

                    if result.type == 'shutdown_all' then
                        M.ipython_down = true
                        logger:info('ipython shutdown complete')
                        pending_msg = ''
                        return
                    elseif result.type == 'execution_result' then
                        local cell = M.cells[result.cell_id]
                        cell:update_extmarks(result)
                    end

                else
                    logger:error('failed to parse: ' .. pending_msg)
                end

            else
                logger:warn('handle_kernel_message: no message found')
            end
            pending_msg = ''
        end
    end
end


--- cell functions -------------------------------------------------------------


--- find the cell currently under the cursor
---@return Cell|nil cell the cell under the cursor
function M.get_cell_under_cursor()
    local pos = vim.api.nvim_win_get_cursor(0)
    local row = pos[1] - 1  -- something something off-by-one
    for _, cell_id in ipairs(M.cell_order) do
        local cell = M.cells[cell_id]
        local s, e = cell:get_range()
        if e > row and row >= s then
            return cell
        end
    end
    logger:info('no cell at row ' .. row)
end


--- step n cells from the current cell, with negative numbers moving backward
--- @param n integer|nil the number of cells to step, default 1
--- @return nil
function M.step_cells(n)
    local cell = M.get_cell_under_cursor()
    local dest_cell

    -- if we are not currently in a cell, we must be at the beginning or
    -- end of the buffer; destination is the first cell
    if cell == nil then
        dest_cell = M.cells[M.cell_order[1]]
    else
        -- find the index of the current cell and then find the cell at index +/- n
        for i, id in ipairs(M.cell_order)do
            if id == cell.id then
                -- subtract 1 before modulo, add back after
                local dest = ((i - 1 + (n or 1)) % #M.cell_order) + 1
                dest_cell = M.cells[M.cell_order[dest]]
                break
            end
        end
    end

    local destination, _ = dest_cell:get_range()
    vim.api.nvim_win_set_cursor(0, {destination + 1, 0})
end


--- send code in the cell under the cursor to the python kernel
--- @return nil
function M.execute_cell_under_cursor()

    if bridge.handle == 0 then
        logger:info('no handle set')
        return
    end

    local cell = M.get_cell_under_cursor()
    if cell == nil or cell.type == 'markdown' then
        return
    end

    local lines = cell:get_input_from_buffer()
    local code = table.concat(lines, '\n')
    local msg = { type = 'exec', code = code, cell_id = cell.id }
    local success = bridge.send_to_subprocess(msg)

    logger:info(tostring(success))
end


--- Open a floating window displaying the cell's output.
--- Window can be closed with 'q' or '<Esc>'.
--- @return nil
function M.open_cell_floating_window()

    local cell = M.get_cell_under_cursor()
    if cell == nil then return end

    local lines, header, row, modifiable
    local buf = vim.api.nvim_create_buf(false, true)
    local nb_buf = vim.api.nvim_get_current_buf()
    local range_start, range_end = cell:get_range()
    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

    if cell.type == 'markdown' then
        lines = cell:get_input_from_buffer()
        row, _ = cell:get_range()
        header = cell.header_txt
        modifiable = true

        -- save changes to markdown cells
        vim.api.nvim_create_autocmd('BufWipeout', {
            buffer = buf,
            callback = function()
                local md_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                vim.api.nvim_buf_set_lines(nb_buf, range_start + 1, range_end, false, md_lines)
            end
        })

    else
        lines = cell:get_output()
        _, row = cell:get_range()
        header = cell.output_txt
        modifiable = false
        row = row - 1
    end

    if #lines == 0 then
        return
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', modifiable)

    vim.api.nvim_open_win(buf, true, {
        relative = 'win',
        bufpos = { row, 0 },
        width = vim.api.nvim_win_get_width(0),
        height = math.min(#lines, math.ceil(vim.api.nvim_win_get_height(0) / 2)),
        border = 'rounded',
        title = ' ' .. header .. ' '
    })

    local opts = { noremap = true, silent = true }
    for _, mode in ipairs({'n', 'v'}) do
        vim.api.nvim_buf_set_keymap(buf, mode, '<Esc>', '<cmd>bd!<CR>', opts)
        vim.api.nvim_buf_set_keymap(buf, mode, '<C-C>', '<cmd>bd!<CR>', opts)
    end
end


return M
