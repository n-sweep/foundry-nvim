local Logging = require('foundry.logging')
local logger = Logging:get_logger('foundry_logger')

local Cell = require('foundry.cell')
local bridge = require('foundry.ipy_bridge')

local M = {
    initialized = false,
    ns = vim.api.nvim_create_namespace('foundry-nvim'),
    keeper = require("otter.keeper"),
    chunk_provider = nil,
    cells = {},
    executor = function() logger:warn('cell executor not set') end,
    supported_langs = { python = true },
}


-- local functions -------------------------------------------------------------


--- Extract all code chunks from the current buffer using the chunk_provider.
--- @return table[] chunks Array of chunk objects with range and lang fields
local function get_chunks()
    local bn = vim.api.nvim_get_current_buf()
    local all_chunks = M.chunk_provider.extract_code_chunks(bn)
    local output = {}
    for _, chunks in pairs(all_chunks) do
        for _, chunk in ipairs(chunks) do
            -- somewhat naive check for frontmatter
            -- yaml frontmatter in a qmd should not be a cell
            if not (chunk.lang == 'yaml' and chunk.range.from[1] == 1) then
                table.insert(output, chunk)
            end
        end
    end
    return output
end


--- Create a new Cell object and register it in M.cells.
--- @param cstart number Starting line of the code block (1-indexed)
--- @param cend number Ending line of the code block (1-indexed)
--- @param lang string Language of the code block (e.g., 'python', 'r', 'bash')
--- @return Cell cell The newly created cell
local function create_cell(cstart, cend, lang)
    local cell = Cell:new(cstart, cend, lang, M.ns, M.opts)
    logger:info('New cell created: ' .. cell.id)
    M.cells[cell.id] = cell
    return cell
end


--- Find the extmark ID that spans the given row position.
--- @param row number Row position (1-indexed) to check
--- @return number id Extmark ID if found, 0 otherwise
local function get_extmark_under_cursor(row)
    local extmarks = vim.api.nvim_buf_get_extmarks(0, M.ns, 0, -1, { details = true })
    for _, extmark in ipairs(extmarks) do
        local id, start_row, details = extmark[1], extmark[2], extmark[4]
        if M.cells[id] and details and details.end_row then
            if row >= start_row and row <= details.end_row then
                return id
            end
        end
    end

    return 0
end


--- Find the code chunk that contains the given row position.
--- @param row number Row position (1-indexed) to check
--- @return table|nil chunk Chunk object with range and lang fields, or nil if not found
local function get_chunk_under_cursor(row)
    local chunks = get_chunks()
    for _, chunk in ipairs(chunks) do
        local start_row = chunk.range.from[1]
        local end_row = chunk.range.to[1]
        if row >= start_row and row <= end_row then
            return chunk
        end
    end

    return nil
end


--- Get or create a cell at the current cursor position.
--- First checks for existing cell extmark, then checks for a code chunk.
--- Creates a new cell if a chunk is found but no cell exists yet.
--- @return Cell|nil cell The cell at cursor position, or nil if none found
local function get_cell_under_cursor()
    local row = vim.api.nvim_win_get_cursor(0)[1]
    local cell_id = get_extmark_under_cursor(row - 1)

    if cell_id > 0 then
        logger:info('cell found: ' .. cell_id)
        return M.cells[cell_id]
    end

    local chunk = get_chunk_under_cursor(row)
    if chunk ~= nil then
        logger:info('new cell created')
        return create_cell(chunk.range.from[1], chunk.range.to[1], chunk.lang)
    end

    vim.notify("No cell found at row " .. row)
    return nil
end


--- Handle execution results from the Python kernel.
--- Parses Jupyter IOPub message format and updates the cell display.
--- @param msg table { cell_id: number, status: "ok"|"error", execution_count: number, messages: table[] }
---   messages[]: { output_type: "stream"|"execute_result"|"error", ... }
local function handle_execution_result(msg)
    local cell = M.cells[msg.cell_id]
    local exc = msg.execution_count
    local content = {}
    local status = 'Done'

    if msg.status == 'error' then
        status = 'Error'
        exc = 'E'
    end

    for _, m in ipairs(msg.messages or {}) do
        local lines = {}

        if m.output_type == 'stream' then
            lines = vim.split(m.text, '\n', { trimempty = true })
        elseif m.output_type == 'execute_result' then
            local text = m.data and m.data['text/plain'] or ''
            lines = vim.split(text, '\n', { trimempty = true })
        elseif m.output_type == 'error' then
            lines = m.traceback and m.traceback['text/plain'] or {}
            logger:error('ipython error reported')
        end

        for _, line in ipairs(lines) do
            table.insert(content, line)
        end
    end

    cell:update(status, exc, content)
end


--- Navigate to the next or previous cell, wrapping at document boundaries.
--- @param dir number Direction: 1 for next, -1 for previous
local function goto_cell(dir)
    local row = vim.api.nvim_win_get_cursor(0)[1] - 1
    local destination = nil
    local min_distance = math.huge
    local min_row = math.huge
    local max_row = -math.huge

    if #M.cells < 1 then
        print('No cells found in this document')
        return
    end

    for _, cell in pairs(M.cells) do
        local cell_row = cell:get_pos()
        local is_valid = (
            dir == 1 and cell_row > row
        ) or (
            dir == -1 and cell_row < row
        )

        min_row = math.min(min_row, cell_row)
        max_row = math.max(max_row, cell_row)

        if is_valid then
            local distance = math.abs(cell_row - row)
            if distance < min_distance then
                min_distance = distance
                destination = cell_row
            end
        end
    end

    -- wrap if at the beginning/end of the page
    if not destination then
        destination = dir == 1 and min_row or max_row
    end

    vim.api.nvim_win_set_cursor(0, {destination + 1, 0})
end


-- Module functions ------------------------------------------------------------


--- Navigate to the next cell, wrapping to the first cell if at the end.
function M.goto_next_cell()
    goto_cell(1)
end


--- Navigate to the previous cell, wrapping to the last cell if at the beginning.
function M.goto_prev_cell()
    goto_cell(-1)
end


--- Open a floating window displaying the cell's output.
--- Window can be closed with 'q' or '<Esc>'.
function M.open_cell_floating_window()
    -- display the cell's output content in a floating window
    -- `q` or `<ESC>` to close the floating window

    local cell = get_cell_under_cursor()
    if cell == nil then return end

    local buf = vim.api.nvim_create_buf(false, true)
    local _, out_header = cell:get_headers()
    local _, row = cell:get_pos()
    local lines = cell.output_lines

    if #lines == 0 then
        return
    end

    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    vim.api.nvim_open_win(buf, true, {
        relative = 'win',
        bufpos = { row - 1, 0 },
        width = vim.api.nvim_win_get_width(0),
        height = math.min(#lines, math.ceil(vim.api.nvim_win_get_height(0) / 2)),
        border = M.opts.border,
        title = ' ' .. out_header .. ' '
    })

    local opts = { noremap = true, silent = true }
    for _, mode in ipairs({'n', 'v'}) do
        vim.api.nvim_buf_set_keymap(buf, mode, '<Esc>', '<cmd>bd!<CR>', opts)
        vim.api.nvim_buf_set_keymap(buf, mode, 'q', '<cmd>bd!<CR>', opts)
    end
end


--- Copy the cell's output to yank registers and system clipboard.
--- Registers: '"' (unnamed), '0' (yank), '+' (system clipboard)
function M.yank_cell_output()
    -- add the cell's output content to yank registers & system clipboard

    local cell = get_cell_under_cursor()
    if cell == nil then return end

    local output = {}
    for i = 1, #cell.output_lines do
        table.insert(output, cell.output_lines[i])
    end

    local text = table.concat(output, '\n')
    for _, reg in ipairs({'"', '0', '+'}) do
        vim.fn.setreg(reg, text)
    end
end


--- Copy the cell's input code to yank registers and system clipboard.
--- Registers: '"' (unnamed), '0' (yank), '+' (system clipboard)
function M.yank_cell_input()
    -- add the cell's input content to yank registers & system clipboard

    local cell = get_cell_under_cursor()
    if cell == nil then return end

    for _, reg in ipairs({'"', '0', '+'}) do
        vim.fn.setreg(reg, cell:get_execution_input())
    end
end


--- Remove cells marked as deleted from the cells table.
--- Used to clean up cells after deletion.
function M.prune_cells()
    local chunks = get_chunks()
    local valid_pos = {}
    for _, chunk in ipairs(chunks) do
        local key = chunk.range.from[1] .. ":" .. chunk.range.to[1]
        valid_pos[key] = true
    end

    -- check all cells for validity and incomplete deletion
    for _, cell in pairs(M.cells) do
        if cell.status == 'deleted' then
            M.cells[cell.id] = nil
        else
            -- convert from 0-indexed (neovim) to 1-indexed (lua) for comparison
            local start_row, end_row = cell:get_pos()
            local key = (start_row + 1) .. ":" .. end_row

            if not valid_pos[key] then
                cell:delete()
                M.cells[cell.id] = nil
            end
        end
    end
end


--- Delete the cell under the cursor and remove it from the cells table.
function M.delete_cell_under_cursor()
    local cell = get_cell_under_cursor()
    if cell ~= nil then
        cell:delete()
        logger:info("cell deleted: " .. cell.id)
        M.cells[cell.id] = nil
    end
end


--- Delete all cells and remove them from the cells table.
function M.delete_all_cells()
    for _, cell in pairs(M.cells) do
        cell:delete()
        logger:info("cell deleted: " .. cell.id)
        M.cells[cell.id] = nil
    end
end


--- Execute the cell under the cursor via the IPython kernel.
--- Updates cell status to 'Running' until execution completes.
function M.execute_cell()
    local cell = get_cell_under_cursor()
    if cell and M.supported_langs[cell.language] then
        local code = cell:get_execution_input()
        logger:info(code)
        M.executor(cell.id, code)
        cell:update('Running', '*', {})
    end
end


--- Handle messages from the IPython kernel.
--- Routes shutdown messages and execution results appropriately.
--- @param message table Message from IPython kernel with type and payload
function M.handle_ipy_message(message)

    if message.type == 'shutdown_all' then
        logger:info('ipython shutdown complete')
        M.ipython_down = true
    else
        handle_execution_result(message)
    end

end


--- Initialize the cell handler module.
--- Starts IPython kernel and creates cells for all code chunks in buffer.
--- @param plugin_root string Root directory of the plugin
--- @param opts table Configuration options
--- @return table M The module table
function M.setup(plugin_root, opts)

    M.opts = opts
    M.executor = bridge.execute

    -- set up chunk provider based on filetype
    local ft = vim.bo.filetype
    if ft == 'python' then
        M.chunk_provider = require('foundry.ipynb_provider')
    else
        M.chunk_provider = {
            extract_code_chunks = function(bn) return M.keeper.extract_code_chunks(bn) end
        }
    end

    -- start the ipython kernel server
    bridge.setup(M, plugin_root)
    bridge.start()

    -- initialize cells
    if not M.initialized then
        local chunks = get_chunks()
        for _, chunk in ipairs(chunks) do
            create_cell(chunk.range.from[1], chunk.range.to[1], chunk.lang)
        end
    end

    M.initialized = true

    return M
end


--- Restart the IPython kernel and clear all cells.
function M.restart_kernel()
    M.delete_all_cells()
    bridge.restart_kernel()
end


--- Shut down the IPython kernel for a specific buffer.
--- @param bufn number Buffer number
function M.shutdown_kernel(bufn)
    M.delete_all_cells()
    bridge.shutdown_kernel(bufn)
end


--- Shut down the entire IPython server and clear all cells.
function M.shutdown_ipython()
    M.delete_all_cells()
    bridge.stop()
end


return M
