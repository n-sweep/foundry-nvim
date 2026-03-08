--- Cell object representing a code block in a quarto document.
--- Manages extmarks for cell boundaries and output display.
---@class Cell
---@field ns number Neovim namespace ID for extmarks
---@field opts table Configuration options
---@field language string Language of the code block
---@field exec_count number|string Execution count or indicator
---@field status string Current status (e.g., "Done", "Error", "Running", "On Hold")
---@field output_lines string[] Output lines from execution
---@field id number Extmark ID for cell boundary
---@field output_id number Extmark ID for output (header + content as virt_lines)
local Cell = {}
Cell.__index = Cell

--- local functions ------------------------------------------------------------

--- Get the currently selected lines in visual mode.
--- @return string[] lines The selected lines
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


--- Limit output to a specific number of lines from start or end.
--- @param lines string[] The lines to limit
--- @param limit number Maximum number of lines to return
--- @param last boolean|nil If true, return last N lines; otherwise first N lines
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


--- Cell Object ----------------------------------------------------------------

--- Create a new Cell object.
--- @param start_row number Starting line of the code block (1-indexed)
--- @param end_row number Ending line of the code block (1-indexed)
--- @param lang string Language of the code block (e.g., 'python', 'r', 'bash')
--- @param namespace number Neovim namespace ID for extmarks
--- @param opts table Configuration options (display_max_lines, etc.)
--- @return Cell cell The new cell object
function Cell:new(start_row, end_row, lang, namespace, opts)
    local obj = {
        ns = namespace,
        opts = opts,
        language = lang,
        exec_count = '...',
        status = 'On Hold',
        output_lines = {},
        id = nil,
        output_id = nil,
    }

    setmetatable(obj, Cell)

    -- mixing 0- and 1-based indexing
    obj:_update_display(start_row - 1, end_row)

    return obj
end


--- Get formatted header strings for input and output display.
--- @return string inp_header Input header (e.g., "In[5] ")
--- @return string out_header Output header (e.g., "Out[5]: Done")
function Cell:get_headers()
    local inp_header = "In[" .. self.exec_count .. "] "
    local out_header = "Out[" .. self.exec_count .. "]: " .. self.status

    return inp_header, out_header
end


--- Update the virtual text display for the cell (private method).
--- Creates/updates extmarks for cell boundary and output.
--- @param start_row number Starting row (0-indexed)
--- @param end_row number Ending row (0-indexed)
function Cell:_update_display(start_row, end_row)

    local inp_header, out_header = self:get_headers()
    local hl_group = 'FoundryCellHL'

    -- truncate text if too long
    local max = self.opts.display_max_lines
    local lines = self.output_lines
    if (max ~= nil) and (#lines > max) then
        lines = truncate_output(lines, max, true)
        out_header = out_header .. '  (' .. #self.output_lines - max .. ' lines truncated)'
    end

    -- prepare lines for virtual text
    local win_width = vim.api.nvim_win_get_width(0)
    local sign_width = vim.fn.getwininfo(vim.fn.win_getid())[1].textoff
    local buf_width = win_width - sign_width
    local vlines = { {{ out_header, hl_group }} }
    for _, line in ipairs(lines) do
        local text_width = vim.fn.strdisplaywidth(line)
        local padding = string.rep(' ', math.max(0, buf_width - text_width))
        table.insert(vlines, {{ line .. padding, hl_group }})
    end

    if self.language == 'markdown' then
        -- no virtual text for markdown cells; extmarks still needed for navigation
        local cell_id = vim.api.nvim_buf_set_extmark(0, self.ns, start_row, 0, {
            id = self.id,
            end_row = end_row,
            end_col = 0,
            end_right_gravity = true,
        })
        local output_id = vim.api.nvim_buf_set_extmark(0, self.ns, end_row, 0, {
            id = self.output_id,
        })
        if self.id == nil then self.id = cell_id end
        if self.output_id == nil then self.output_id = output_id end
        return
    end

    if self.language ~= 'python' then
        inp_header = ''
    end

    -- create/update cell extmarks
    local cell_id = vim.api.nvim_buf_set_extmark(0, self.ns, start_row, 0, {
        id = self.id,
        end_row = end_row,
        end_col = 0,
        end_right_gravity = true,
        virt_text = {{ inp_header, hl_group }},
        virt_text_pos = 'eol',
    })

    if self.id == nil then
        self.id = cell_id
    end

    local output_id = vim.api.nvim_buf_set_extmark(0, self.ns, end_row, 0, {
        id = self.output_id,
        virt_lines = vlines,
        virt_lines_above = true,
    })

    if self.output_id == nil then
        self.output_id = output_id
    end
end


--- Get extmark data by ID (private method).
--- @param id number Extmark ID to retrieve
--- @return table extmark Extmark data with position and details
function Cell:_get_extmark(id)
    return vim.api.nvim_buf_get_extmark_by_id(0, self.ns, id, { details = true })
end


--- Get the current position of the cell in the buffer.
--- @return number start_row Starting row (0-indexed)
--- @return number end_row Ending row (0-indexed)
function Cell:get_pos()
    local em = self:_get_extmark(self.id)
    return em[1], em[3].end_row
end


--- Update the cell's execution state and display.
--- @param status string Status message (e.g., "Done", "Error", "Running")
--- @param exec number|string Execution count or indicator
--- @param lines string[] Output lines to display
function Cell:update(status, exec, lines)
    self.exec_count, self.status, self.output_lines = exec, status, lines
    self:_update_display(self:get_pos())
end


--- Delete the cell's extmarks, clearing all associated virtual text.
--- Sets status to 'deleted' so cell_handler can remove it from M.cells.
function Cell:delete()
    vim.api.nvim_buf_del_extmark(0, self.ns, self.id)
    vim.api.nvim_buf_del_extmark(0, self.ns, self.output_id)

    -- the Cell object does not know about the cell handler that stores Cells
    -- cell handler must be able to remove deleted Cells from its memory
    self.status = 'deleted'
end


--- Get the code content to execute from this cell.
--- If in visual mode, returns selected lines; otherwise returns all cell lines.
--- @return string code Trimmed code content ready for execution
function Cell:get_execution_input()
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
