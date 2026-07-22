local M = {
    ns = vim.api.nvim_create_namespace('foundry-nvim'),
    cells = {},
    cell_order = {},
}

local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

local Cell = require('foundry.cell')
local bridge = require('foundry.ipy_bridge')
local utils = require('foundry.utils')
local undo_redo = require('foundry.undo_redo')

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


--- return the kernel info
--- @param bufn number|nil Buffer number (defaults to current buffer)
--- @return boolean success Whether the command was sent successfully
function M.get_kernel_info(bufn)
    return bridge.send_to_subprocess({ type = 'info', target = 'kernel' }, bufn)
end


--- calls to the python backend to read a jupyter notebook
--- @param file string location of the notebook to be read
--- @return nil
function M.load_notebook(file)
    local msg
    if vim.fn.filereadable(file) == 1 then
        msg = { command = { 'read', file } }
    else
        logger:info(file .. ' not found, creating...')
        msg = { command = { 'create', file } }
    end

    local result = bridge.run_python_command(msg, M.handle_kernel_message)
    if result then
        logger:info(file .. ' loaded')
        M.cells = {}
        M.cell_order = {}
        for _, data in ipairs(result.cells) do
            local cell = Cell:new(M.ns, data)
            M.cells[cell.id] = cell
            table.insert(M.cell_order, cell.id)
        end

        -- place cells in buffer and ensure it's not undoable
        local ul = vim.bo.undolevels
        vim.bo.undolevels = -1
        M.place_cells()
        vim.bo.undolevels = ul

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


--- Redraw the header
--- @return nil
function M.draw_header()
    local title = 'Notebook: ' .. vim.api.nvim_buf_get_name(0)
    local text = {'Loading...'}

    if M.info then
        text = {
            'VENV: ' .. bridge.venv,
            'Python: ' .. M.info.language_info.version,
            'IPython: ' .. M.info.implementation_version,
            'Plot Server: ' .. M.info.image_server,
        }
    end

    M.header = vim.api.nvim_buf_set_extmark(0, M.ns, 0, 0, {
        id = M.header,
        virt_text = utils.prep_vtext(title),
        virt_text_pos = 'overlay',
        virt_lines = utils.prep_vtext(text, true),
    })

end


--- Clear the buffer and place the header and cells in the buffer
--- @return nil
function M.place_cells()
    vim.api.nvim_buf_clear_namespace(0, M.ns, 0, -1)
    vim.api.nvim_buf_set_lines(0, 0, -1, false, {'', ''})

    M.draw_header()

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
                        cell.status = 'Done'
                        cell:update_extmarks(result)

                    elseif result.type == 'error' then
                        local cell = M.cells[result.cell_id]
                        cell.status = 'Error'
                        cell:update_extmarks(result)

                    elseif result.type == 'info' then
                        M.info = result
                        M.draw_header()
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
            logger:info('cell found: ' .. cell.id)
            return cell
        end
    end
    logger:info('no cell at row ' .. row)
end


--- step n cells from the current cell, with negative numbers moving backward
--- @param n integer|nil the number of cells to step, default 1
--- @param cell Cell|nil the cell under the cursor
--- @return nil
function M.step_cells(n, cell)
    cell = cell or M.get_cell_under_cursor()
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
--- @return Cell|nil cell the cell executed
function M.execute_cell_under_cursor()

    if bridge.handle == 0 then
        logger:info('no handle set')
        return
    end

    local cell = M.get_cell_under_cursor()
    if cell == nil or cell.type == 'markdown' then
        return
    end

    cell.status = 'In Process...'
    cell:update_extmarks()

    local lines = cell:get_input_from_buffer()
    local code = table.concat(lines, '\n')
    local msg = { type = 'exec', code = code, cell_id = cell.id }
    local success = bridge.send_to_subprocess(msg)

    logger:info('cell ' .. cell.id .. ': ' .. tostring(success))

    return cell
end


--- delete a cell by cell id
--- @param cell_id string
--- @return nil
function M.delete_cell_by_id(cell_id)
    local cell = M.cells[cell_id]

    local idx
    for i, v in ipairs(M.cell_order) do
        if v == cell_id then
            idx = i
            break
        end
    end

    local s, e = cell:get_range()
    local next_cell = M.cells[M.cell_order[idx + 1]]
    local seq_before = vim.fn.undotree().seq_cur

    vim.api.nvim_buf_set_lines(0, s + 1, e + 1, false, {})

    -- delete the cell's extmarks
    vim.api.nvim_buf_del_extmark(0, M.ns, cell.header_id)
    vim.api.nvim_buf_del_extmark(0, M.ns, cell.output_id)

    -- reposition next cell's header_id to the now-exposed boundary row (s) and refresh its decorations
    if next_cell then
        vim.api.nvim_buf_set_extmark(0, M.ns, s, 0, {
            id = next_cell.header_id,
        })
        next_cell:update_extmarks()
    end

    table.remove(M.cell_order, idx)
    M.cells[cell_id] = nil

    table.insert(undo_redo.undo_stack, {
        type = 'delete',
        cell = cell,
        idx = idx,
        next_cell_id = next_cell and next_cell.id or nil,
        seq_before = seq_before,
        seq_after = vim.fn.undotree().seq_cur,
    })
    undo_redo.redo_stack = {}
end


--- delete the selected cell
--- @return nil
function M.delete_cell_under_cursor()
    local cell = M.get_cell_under_cursor()
    if cell == nil then return end

    M.delete_cell_by_id(cell.id)
end


--- create a new cell
--- @param type string the type of cell to be created
--- @param above? boolean whether to create the new cell above the current cell
--- @return Cell|nil new_cell
function M.create_cell(type, above)
    local cell = M.get_cell_under_cursor()

    -- handle cursor being on the pre-first or post-last buffer line
    if cell == nil then
        local row = vim.api.nvim_win_get_cursor(0)[1] - 1
        local first_cell = M.cells[M.cell_order[1]]
        if first_cell == nil then return end
        local start, _ = first_cell:get_range()
        if row < start then -- cursor is at the top of the buffer
            cell = first_cell
            above = true
        else -- bottom of buffer
            cell = M.cells[M.cell_order[#M.cell_order]]
            above = false
        end
    end

    local new_cell = Cell:new(M.ns, {
        id = (vim.fn.system("uuidgen"):gsub("\n", "")),
        cell_type = type,
        source = '',
    })

    local idx
    for i, v in ipairs(M.cell_order) do
        if v == cell.id then
            idx = i + (above and 0 or 1)
            break
        end
    end

    table.insert(M.cell_order, idx, new_cell.id)
    M.cells[new_cell.id] = new_cell

    -- find the boundary row to insert at and the next cell (if any)
    local boundary_row, next_cell
    local s, e = cell:get_range()
    if above then
        -- inserting above current cell
        boundary_row = s
        next_cell = cell
    else
        -- inserting below current cell
        boundary_row = e
        local next_id = M.cell_order[idx + 1]
        if next_id then next_cell = M.cells[next_id] end
    end

    -- place the new cell starting at the boundary row
    local seq_before = vim.fn.undotree().seq_cur
    new_cell:place_in_buffer(boundary_row)

    -- reposition next cell's header_id to new cell's output row and refresh its outputs
    if next_cell then
        local _, new_output_row = new_cell:get_range()
        vim.api.nvim_buf_set_extmark(0, M.ns, new_output_row, 0, {
            id = next_cell.header_id,
        })
        next_cell:update_extmarks()
    end

    table.insert(undo_redo.undo_stack, {
        type = 'create',
        cell = new_cell,
        idx = idx,
        next_cell_id = next_cell and next_cell.id or nil,
        seq_before = seq_before,
        seq_after = vim.fn.undotree().seq_cur,
    })
    undo_redo.redo_stack = {}

    vim.api.nvim_win_set_cursor(0, { boundary_row + 2, 0 })

    return new_cell
end


--- Move the cell under the cursor up or down by one position
--- @param direction integer 1 for down, -1 for up
--- @return nil
function M.move_cell(direction)
    local cell = M.get_cell_under_cursor()
    if cell == nil then return end

    local idx
    for i, id in ipairs(M.cell_order) do
        if id == cell.id then idx = i; break end
    end

    local new_idx = idx + direction
    if new_idx < 1 or new_idx > #M.cell_order then return end

    local seq_before = vim.fn.undotree().seq_cur

    M.cell_order[idx], M.cell_order[new_idx] = M.cell_order[new_idx], M.cell_order[idx]

    -- sync live buffer content into cell.data.source before redraw
    for _, id in ipairs(M.cell_order) do
        local c = M.cells[id]
        local lines = c:get_input_from_buffer()
        c.data.source = table.concat(lines, '\n')
    end

    local ul = vim.bo.undolevels
    vim.bo.undolevels = -1
    M.place_cells()
    vim.bo.undolevels = ul

    table.insert(undo_redo.undo_stack, {
        type       = 'move',
        cell       = cell,
        idx        = idx,
        new_idx    = new_idx,
        seq_before = seq_before,
        seq_after  = vim.fn.undotree().seq_cur,
    })
    undo_redo.redo_stack = {}

    local s, _ = cell:get_range()
    vim.api.nvim_win_set_cursor(0, { s + 1, 0 })
end

--- yank the cell's output or input to the unnamed and system clipboard registers
--- @param output boolean|nil if true, yank the cell's output (default); if false, yank the cell's input
--- @return nil
function M.yank_cell(output)
    local cell = M.get_cell_under_cursor()
    if cell == nil then return end

    local lines
    if output == nil then output = true end
    if output then
        lines = cell:get_output()
    else
        lines = cell:get_input_from_buffer()
    end

    local text = table.concat(lines, '\n')
    for _, reg in ipairs({'"', "+"}) do
        vim.fn.setreg(reg, text)
    end
end


--- Open a floating window displaying the cell's output.
--- @return nil
function M.open_cell_floating_window()

    local cell = M.get_cell_under_cursor()
    if cell == nil then return end

    local buf = vim.api.nvim_create_buf(false, true)
    local nb_buf = vim.api.nvim_get_current_buf()
    local range_start, range_end = cell:get_range()
    local lines, header, row, modifiable, border

    vim.api.nvim_buf_set_option(buf, 'bufhidden', 'wipe')

    if cell.type == 'markdown' then
        row = range_start
        header = cell.header_txt
        modifiable = true
        border = 'none'
        lines = cell:get_input_from_buffer()
        vim.api.nvim_buf_set_option(buf, "filetype", "markdown")

        -- save changes to markdown cells
        vim.api.nvim_create_autocmd('BufWipeout', {
            buffer = buf,
            callback = function()
                local md_lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
                for i, line in ipairs(md_lines) do md_lines[i] = '# ' .. line end
                vim.api.nvim_buf_set_lines(nb_buf, range_start + 1, range_end, false, md_lines)
            end
        })

    else
        row = range_end - 1
        header = cell.output_txt
        lines = cell:get_output()
        modifiable = false
        border = 'rounded'
    end

    if #lines == 0 then return end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.api.nvim_buf_set_option(buf, 'modifiable', modifiable)

    local parent_win = vim.api.nvim_get_current_win()
    local win = vim.api.nvim_open_win(buf, true, {
        relative = 'win',
        bufpos = { row, 0 },
        width = vim.api.nvim_win_get_width(parent_win),
        height = math.min(#lines, math.ceil(vim.api.nvim_win_get_height(parent_win) / 2)),
        border = border,
        title = ' ' .. header .. ' '
    })

    -- resize floating window on text change in markdown cells
    -- (modifiable = false; ignored in code output cells)
    vim.api.nvim_create_autocmd({'TextChanged', 'InsertLeave'}, {
        buffer = buf,
        callback = function()
            local line_count = vim.api.nvim_buf_line_count(buf)
            local max_height = math.ceil(vim.api.nvim_win_get_height(parent_win) / 2)
            vim.api.nvim_win_set_config(win, { height = math.min(line_count, max_height) })
        end,
    })

    local opts = { noremap = true, silent = true }
    for _, key in ipairs({'<Esc>', '<C-C>', '<leader>qq', '<leader>w'}) do
        for _, mode in ipairs({'n', 'v'}) do
            vim.api.nvim_buf_set_keymap(buf, mode, key, '<cmd>bd!<CR>', opts)
        end
    end
end


return M
