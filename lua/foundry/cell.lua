local Cell = {}
Cell.__index = Cell

-- local Logging = require('foundry.logging')
-- local logger = Logging:get_logger('foundry_logger')


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


local function limit_lines(lines, limit, last)
    local _start, _end
    local output = {}

    if last == nil then
        _start, _end = 1, limit + 1
    else
        _start, _end = #lines - limit + 1, #lines
    end

    for i = _start, _end do
        table.insert(output, lines[i])
    end

    return output
end


local function truncate_output(lines, limit, middle)
    local output, top, bot = {}, {}, {}

    if middle == nil then
        top = limit_lines(lines, limit)
    else
        local lh = limit / 2
        local lt, lb = math.ceil(lh), math.floor(lh)
        top = limit_lines(lines, lt)
        bot = limit_lines(lines, lb, true)
    end

    for _, tbl in ipairs({ top, { '...' }, bot }) do
        for _, line in ipairs(tbl) do
            table.insert(output, line)
        end
    end

    return output
end


function Cell:new(start_row, end_row, namespace, opts)
    local obj = {
        ns = namespace,
        opts = opts,
        exec_count = '...',
        status = 'On Hold',
        output_lines = {},
        id = nil,
        output_id = nil,
    }

    setmetatable(obj, Cell)

    -- mixing 0- and 1-based indexing
    obj:_update_display(start_row - 1, end_row - 1)

    return obj
end


function Cell:get_headers()
    local inp_header = "In[" .. self.exec_count .. "] "
    local out_header = "Out[" .. self.exec_count .. "]: " .. self.status

    return inp_header, out_header
end


function Cell:_update_display(start_row, end_row)
    -- update the virtual text associated with the cell

    local inp_header, out_header = self:get_headers()

    -- truncate text if too long
    local max = self.opts.display_max_lines
    local lines = self.output_lines
    if (max ~= nil) and (#lines > max) then
        lines = truncate_output(lines, max, true)
        out_header = out_header .. '  (' .. #self.output_lines - max .. ' lines truncated)'
    end

    -- prepare lines for virtual text
    local vlines = { {{ out_header, 'Comment' }} }
    for _, line in ipairs(lines) do
        table.insert(vlines, {{ line, 'Comment' }})
    end

    -- create/update cell extmarks
    local out_opts = {
        id = self.output_id,
        virt_lines = vlines,
        virt_lines_above = true
    }

    local inp_opts = {
        id = self.id,
        end_row = end_row,
        end_col = 0,
        end_right_gravity = true,
        virt_text = {{ inp_header, 'Comment' }},
        virt_text_pos = 'inline',
    }

    local cell_id = vim.api.nvim_buf_set_extmark(0, self.ns, start_row, 0, inp_opts)
    local output_id = vim.api.nvim_buf_set_extmark(0, self.ns, end_row, 0, out_opts)

    -- if cell is being newly created, store ids
    if self.id == nil then
        self.id = cell_id
    end

    if self.output_id == nil then
        self.output_id = output_id
    end

end


function Cell:_get_extmark()
    return vim.api.nvim_buf_get_extmark_by_id(0, self.ns, self.id, { details = true })
end


function Cell:get_pos()
    local em = self:_get_extmark()
    return em[1], em[3].end_row
end


function Cell:update(status, exec, lines)
    -- update the cell's display
    self.exec_count, self.status, self.output_lines = exec, status, lines
    self:_update_display(self:get_pos())
end


function Cell:delete()
    -- delete the cell's extmarks, clearing all associated virtual text
    vim.api.nvim_buf_del_extmark(0, self.ns, self.id)
    vim.api.nvim_buf_del_extmark(0, self.ns, self.output_id)

    -- the Cell object does not know about the cell handler that stores Cells
    -- cell handler must be able to remove deleted Cells from its memory
    self.status = 'deleted'
end


function Cell:is_valid()
    local start_row, end_row = self:get_pos()

    -- if start and end are equal, all the cell's input content has been deleted from the buffer
    if start_row >= end_row then
        return false

    -- the cell is invalid if its separator has been deleted
    elseif string.find(vim.fn.getline(start_row + 1), "^# %%") == nil then
        return false
    end

    return true
end


function Cell:get_execution_input()
    -- get the content of the input section of the cell
    local start_row, end_row = self:get_pos()
    local lines = {}

    -- prioritize selections
    local mode = vim.api.nvim_get_mode()['mode']
    if mode == 'v' or mode == 'V' or mode == '^V' then
        lines = get_selected_lines()
        vim.api.nvim_input('<Esc>')  -- exit select mode
    else
        lines = vim.fn.getline(start_row + 2, end_row)
    end

    return table.concat(lines, '\n'):match("^%s*(.-)%s*$")
end


return Cell
