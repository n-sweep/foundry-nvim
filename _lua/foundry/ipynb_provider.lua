local M = {}


--- Extract all code chunks from a buffer using `# %%` delimiters.
--- Skips markdown cells and empty cells (adjacent delimiters).
--- @param bufnr number Buffer number
--- @return table chunks { python = { chunk, ... } } where each chunk has range and lang fields
function M.extract_code_chunks(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local nlines = #lines

    -- collect all delimiter positions; markdown delimiters act as boundaries
    -- but do not produce code chunks
    local delimiters = {}
    for i, line in ipairs(lines) do
        if line:match('^# %%%%') then
            table.insert(delimiters, { line = i, is_markdown = line:match('markdown') ~= nil })
        end
    end

    local python_chunks = {}
    local markdown_chunks = {}
    for i, d in ipairs(delimiters) do
        local next_d = delimiters[i + 1]
        local to = next_d and (next_d.line - 1) or nlines
        local lang = d.is_markdown and 'markdown' or 'python'

        -- trim trailing blank lines
        while to > d.line and lines[to] == '' do
            to = to - 1
        end

        -- skip empty cells (adjacent delimiters)
        if d.line + 1 <= to then
            local chunk = {
                range = { from = { d.line, 0 }, to = { to, 0 } },
                lang = lang,
            }
            if lang == 'markdown' then
                table.insert(markdown_chunks, chunk)
            else
                table.insert(python_chunks, chunk)
            end
        end
    end

    return { python = python_chunks, markdown = markdown_chunks }
end


--- Find the chunk that contains the given row.
--- @param row number Row position (1-indexed, matches vim cursor convention)
--- @return table|nil chunk Chunk object, or nil if not found
function M.get_chunk_under_cursor(row)
    local bufnr = vim.api.nvim_get_current_buf()
    local result = M.extract_code_chunks(bufnr)
    for _, chunk in ipairs(result.python or {}) do
        if row >= chunk.range.from[1] and row <= chunk.range.to[1] then
            return chunk
        end
    end
    return nil
end


return M
