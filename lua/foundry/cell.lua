-- local Logging = require('foundry.logging')
-- local logger = Logging:get_logger('foundry_logger')
local utils = require('foundry.utils')

--- local functions ------------------------------------------------------------


--- Limit output to a specific number of lines from start or end.
--- @param lines string[] The lines to limit
--- @param limit number Maximum number of lines to return
--- @param last? boolean If true, return last N lines; otherwise first N lines
--- @return string[] limited_lines The limited output
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


--- Truncate long output by showing first and last lines with '...' in between.
--- @param lines string[] The lines to truncate
--- @param limit number Maximum number of lines to show
--- @param middle boolean|nil If true, show first/last; otherwise show first N only
--- @return string[] truncated_lines The truncated output
local function truncate_output(lines, limit, middle)
    local output, top, bot = {}, {}, {}

    if middle == nil then
        top = limit_lines(lines, limit)
    else
        local lh = limit / 2
        local lt, lb = math.floor(lh), math.ceil(lh)
        top = limit_lines(lines, lt)
        bot = limit_lines(lines, lb, true)
    end

    for _, tbl in ipairs({ top, { '...' }, bot }) do
        vim.list_extend(output, tbl)
    end

    return output
end



--- cell object-----------------------------------------------------------------

--- Cell object representing a jupyter notebook cell
--- Manages extmarks for cell boundaries and output display.
---@class Cell
---@field ns number Neovim namespace ID for extmarks
---@field data table Cell data from Jupyter
---@field status string Current status (e.g., "Done", "Error", "Running", "On Hold")
---@field header_id number Extmark ID for cell header
---@field header_txt string Extmark input header content
---@field output_id number Extmark ID for cell output
---@field output_txt string Extmark output header content
---@field id string Jupyter cell id
---@field type string Cell type
---@field exec_count number|string Execution count or indicator
local Cell = {}
Cell.__index = Cell


--- Create a new Cell object.
--- @param namespace number Neovim namespace ID for extmarks
--- @param data table cell data including inputs and outputs
--- @return Cell cell The new cell object
function Cell:new(namespace, data)
    local obj = {
        ns = namespace,
        data = data,
        status = 'On Hold',
    }

    local mt = {
        -- getter
        __index = function(t, key)
            if key == 'id' then
                return t.data.id

            elseif key == 'type' then
                return t.data.cell_type

            elseif key == 'exec_count' then
                if data['execution_count'] ~= vim.NIL then
                    return data['execution_count']
                else
                    return '...'
                end

            -- elseif key == '' then
            end
            return Cell[key]
        end,

        -- setter
        __newindex = function(t, key, value)
            if t.data[key] ~= nil then
                t.data[key] = value
            else
                rawset(t, key, value)
            end
        end
    }

    setmetatable(obj, mt)

    return obj
end


--- Get the range of rows that the cell contains
--- @return integer, integer range the start and end rows of the cell
function Cell:get_range()
    local header_mark = vim.api.nvim_buf_get_extmark_by_id(0, self.ns, self.header_id, {})
    local output_mark = vim.api.nvim_buf_get_extmark_by_id(0, self.ns, self.output_id, {})
    return header_mark[1], output_mark[1]
end


--- Get the text content of the cell's input field
--- @return table lines a table of strings containing the cell's input text
function Cell:get_input_from_buffer()
    local s, e = self:get_range()
    local lines = vim.fn.getline(s + 2, e)  -- something something off-by-one
    if self.type == 'markdown' then
        for i, line in ipairs(lines) do
            lines[i] = line:gsub('^# ', '')
        end
    end
    return lines
end


--- Get the cell's output content from the underlying jupyter data
--- @return table lines a table of strings containing the cell's output text
function Cell:get_output()
    local cell_output = {}
    for _, output in ipairs(self.data.outputs) do
        if output.output_type == 'stream' then
            local text = vim.split(output.text, '\n', {trimempty = true})
            vim.list_extend(cell_output, text)
        elseif output.output_type == 'execute_result' then
            table.insert(cell_output, output.data['text/plain'])
        end
    end
    return cell_output
end


--- update the header and output text of the cell
--- @param msg? table the result message from an execution to update the cell
function Cell:update_extmarks(msg)
    if msg ~= nil then
        self.exec_count = msg.execution_count
        self.data.outputs = msg.outputs
    end

    -- generate cell header and output
    local cell_output = {}

    if self.type == 'markdown' then
        -- markdown gets no output field
        self.header_txt = '- [markdown]'

    elseif self.type == 'code' then
        local cs = '[' .. tostring(self.exec_count) .. ']'
        self.header_txt = 'In ' .. cs .. ' ' .. self.status
        self.output_txt = 'Out ' .. cs

        -- truncate text if too long
        local max = 15 -- self.opts.display_max_lines
        local lines = self:get_output()
        local nlines = #lines
        if (max ~= nil) and (nlines > max) then
            lines = truncate_output(lines, max, true)
            self.output_txt = self.output_txt .. '  (' .. nlines - max .. ' lines truncated)'
        end

        table.insert(cell_output, self.output_txt)

        -- add cell output content
        vim.list_extend(cell_output, lines)
    end

    -- update header
    local imark = vim.api.nvim_buf_get_extmark_by_id(0, self.ns, self.header_id, { details = true })
    vim.api.nvim_buf_set_extmark(0, self.ns, imark[1], 0, {
        id = self.header_id,
        virt_text = utils.prep_vtext(self.header_txt, nil, '-'),
        end_col = 0,
        virt_text_pos = 'overlay',
    })

    -- update output
    local omark = vim.api.nvim_buf_get_extmark_by_id(0, self.ns, self.output_id, { details = true })
    vim.api.nvim_buf_set_extmark(0, self.ns, omark[1], 0, {
        id = self.output_id,
        virt_lines = utils.prep_vtext(cell_output, true),
        virt_lines_above = true,
    })
end


--- Create extmarks for cell header and output fields and place in buffer
--- @param row integer The row to place the cell header on (0-based)
function Cell:place_in_buffer(row)
    -- create cell header extmark
    if row == nil then
        row = vim.api.nvim_buf_line_count(0) - 1
    end
    self.header_id = vim.api.nvim_buf_set_extmark(0, self.ns, row, 0, {})

    -- insert cell input lines into buffer after header row
    local cell_input = vim.split(self.data.source, '\n')
    if self.type == 'markdown' then
        for i, line in ipairs(cell_input) do
            cell_input[i] = '# ' .. line
        end
    end
    vim.api.nvim_buf_set_lines(0, row + 1, row + 1, false, cell_input)
    vim.api.nvim_buf_set_lines(0, row + 1 + #cell_input, row + 1 + #cell_input, false, {''})

    -- create cell output extmark on the blank separator line
    local output_row = row + #cell_input + 1
    self.output_id = vim.api.nvim_buf_set_extmark(0, self.ns, output_row, 0, {})

    self:update_extmarks()
end


return Cell
