local M = {
    undo_stack = {},
    redo_stack = {},
}

local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

--- get the output_id row of the cell before idx, or row 1 if idx is the first cell
--- @param idx integer 1-based index into cell_order
--- @param state table the core state of the application (core.lua)
--- @return integer boundary_row
local function get_boundary_row(idx, state)
    local prev_id = state.cell_order[idx - 1]
    local prev_cell = prev_id and state.cells[prev_id]
    if prev_cell then
        local _, e = prev_cell:get_range()
        return e
    else
        return 1
    end
end

--- restore a cell into lua state and recreate its extmarks
--- @param entry table undo/redo entry
--- @param state table
--- @return nil
local function restore_cell(entry, state)
    state.cells[entry.cell.id] = entry.cell
    table.insert(state.cell_order, entry.idx, entry.cell.id)

    local boundary_row = get_boundary_row(entry.idx, state)
    entry.cell.header_id = vim.api.nvim_buf_set_extmark(0, state.ns, boundary_row, 0, {})

    local output_row = boundary_row + #vim.split(entry.cell.data.source, '\n') + 1
    entry.cell.output_id = vim.api.nvim_buf_set_extmark(0, state.ns, output_row, 0, {})
    entry.cell:update_extmarks()

    local next_cell = entry.next_cell_id and state.cells[entry.next_cell_id]
    if next_cell then
        vim.api.nvim_buf_set_extmark(0, state.ns, output_row, 0, { id = next_cell.header_id })
        next_cell:update_extmarks()
    end
end


--- remove a cell from lua state and delete its extmarks
--- @param entry table undo/redo entry
--- @param state table
--- @return nil
local function remove_cell(entry, state)
    state.cells[entry.cell.id] = nil
    table.remove(state.cell_order, entry.idx)

    vim.api.nvim_buf_del_extmark(0, state.ns, entry.cell.header_id)
    vim.api.nvim_buf_del_extmark(0, state.ns, entry.cell.output_id)

    local next_cell = entry.next_cell_id and state.cells[entry.next_cell_id]
    if next_cell then
        local boundary_row = get_boundary_row(entry.idx, state)
        vim.api.nvim_buf_set_extmark(0, state.ns, boundary_row, 0, { id = next_cell.header_id })
        next_cell:update_extmarks()
    end
end


--- undo one cell create/delete operation; called after the buffer undo has already been applied
--- @param state table the core state of the application (core.lua)
--- @return nil
function M.handle_undo(state)
    local entry = M.undo_stack[#M.undo_stack]
    if not entry then return end
    if vim.fn.undotree().seq_cur ~= entry.seq_before then return end
    table.remove(M.undo_stack)
    table.insert(M.redo_stack, entry)

    if entry.type == 'create' then
        remove_cell(entry, state)
    elseif entry.type == 'delete' then
        restore_cell(entry, state)
    end
end


--- redo one cell create/delete operation; called after the buffer redo has already been applied
--- @param state table the core state of the application (core.lua)
--- @return nil
function M.handle_redo(state)
    local entry = M.redo_stack[#M.redo_stack]
    if not entry then return end
    if vim.fn.undotree().seq_cur ~= entry.seq_after then return end
    table.remove(M.redo_stack)
    table.insert(M.undo_stack, entry)

    if entry.type == 'create' then
        restore_cell(entry, state)
    elseif entry.type == 'delete' then
        remove_cell(entry, state)
    end
end


return M
