-- local Logging = require('foundry.logging')
-- local logger = Logging:get_logger('foundry_logger')
local utils = require('foundry.utils')

--- Cell object representing a jupyter notebook cell
--- Manages extmarks for cell boundaries and output display.
---@class Cell
---@field ns number Neovim namespace ID for extmarks
---@field data table Cell data from Jupyter
---@field status string Current status (e.g., "Done", "Error", "Running", "On Hold")
---@field header_id number Extmark ID for cell header
---@field output_id number Extmark ID for cell output
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
        header_id = nil,
        output_id = nil,
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
    return vim.fn.getline(s + 2, e)  -- something something off-by-one
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
    local cell_header = ''

    if self.type == 'markdown' then
        -- markdown gets no output field
        cell_header = cell_header .. '- [markdown]'

    elseif self.type == 'code' then
        -- build input and output headers
        local cs = '[' .. tostring(self.exec_count) .. ']'
        local in_cs, out_cs = 'In ' .. cs, 'Out ' .. cs
        cell_header = cell_header .. in_cs .. ' ' .. self.status
        table.insert(cell_output, out_cs)

        -- add cell output content
        vim.list_extend(cell_output, self:get_output())
    end

    -- update header
    local imark = vim.api.nvim_buf_get_extmark_by_id(0, self.ns, self.header_id, { details = true })
    vim.api.nvim_buf_set_extmark(0, self.ns, imark[1], 0, {
        id = self.header_id,
        virt_text = utils.prep_vtext(cell_header, nil, '-'),
        end_col = 0,
        virt_text_pos = 'overlay',
        end_right_gravity = true,
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
function Cell:place_in_buffer(row)
    -- create cell header extmark
    if row == nil then
        row = vim.api.nvim_buf_line_count(0) - 1
    end
    self.header_id = vim.api.nvim_buf_set_extmark(0, self.ns, row, 0, {})

    -- insert cell input lines into buffer
    local cell_input = vim.split(self.data.source, '\n')
    vim.api.nvim_buf_set_lines(0, -1, -1, false, cell_input)
    vim.api.nvim_buf_set_lines(0, -1, -1, false, {''})

    -- create cell output extmark
    row = row + #cell_input + 1
    self.output_id = vim.api.nvim_buf_set_extmark(0, self.ns, row, 0, {})

    self:update_extmarks()
end


return Cell
