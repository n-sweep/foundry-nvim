describe('ipynb_provider', function()
    local provider
    local buf

    before_each(function()
        package.loaded['foundry.ipynb_provider'] = nil
        provider = require('foundry.ipynb_provider')
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)
    end)

    after_each(function()
        package.loaded['foundry.ipynb_provider'] = nil
        vim.api.nvim_buf_delete(buf, { force = true })
    end)


    describe('extract_code_chunks', function()

        it('detects a single cell', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
                'y = 2',
            })
            local result = provider.extract_code_chunks(buf)
            assert.is_not_nil(result.python)
            assert.are.equal(1, #result.python)
            local chunk = result.python[1]
            assert.are.equal(1, chunk.range.from[1])
            assert.are.equal(3, chunk.range.to[1])
            assert.are.equal('python', chunk.lang)
        end)

        it('detects multiple cells with correct ranges', function()
            -- line 1: # %%
            -- line 2: x = 1        <- cell 1 content (to[1]=2, blank trimmed)
            -- line 3:              <- blank (excluded from cell 1)
            -- line 4: # %%
            -- line 5: y = 2        <- cell 2 content
            -- line 6: z = 3        <- cell 2 content (to[1]=6, EOF)
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
                '',
                '# %%',
                'y = 2',
                'z = 3',
            })
            local result = provider.extract_code_chunks(buf)
            assert.are.equal(2, #result.python)
            assert.are.equal(1, result.python[1].range.from[1])
            assert.are.equal(2, result.python[1].range.to[1])
            assert.are.equal(4, result.python[2].range.from[1])
            assert.are.equal(6, result.python[2].range.to[1])
        end)

        it('last cell range extends to end of buffer', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
                'y = 2',
                'z = 3',
            })
            local result = provider.extract_code_chunks(buf)
            assert.are.equal(1, #result.python)
            assert.are.equal(4, result.python[1].range.to[1])
        end)

        it('skips empty cells (adjacent delimiters)', function()
            -- line 1: # %%     <- empty cell (no content before next delimiter)
            -- line 2: # %%
            -- line 3: x = 1
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                '# %%',
                'x = 1',
            })
            local result = provider.extract_code_chunks(buf)
            assert.are.equal(1, #result.python)
            assert.are.equal(2, result.python[1].range.from[1])
            assert.are.equal(3, result.python[1].range.to[1])
        end)

        it('skips markdown cells', function()
            -- line 1: # %%           <- cell 1 (to[1]=2, blank trimmed)
            -- line 2: x = 1
            -- line 3:                <- blank (excluded)
            -- line 4: # %% markdown  <- markdown cell (not in python chunks)
            -- line 5: # some text
            -- line 6:                <- blank (excluded)
            -- line 7: # %%           <- cell 2 (to[1]=8, EOF)
            -- line 8: y = 2
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
                '',
                '# %% markdown',
                '# some text',
                '',
                '# %%',
                'y = 2',
            })
            local result = provider.extract_code_chunks(buf)
            assert.are.equal(2, #result.python)
            assert.are.equal(1, result.python[1].range.from[1])
            assert.are.equal(2, result.python[1].range.to[1])
            assert.are.equal(7, result.python[2].range.from[1])
            assert.are.equal(8, result.python[2].range.to[1])
        end)

        it('returns empty list when no delimiters found', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                'x = 1',
                'y = 2',
            })
            local result = provider.extract_code_chunks(buf)
            assert.is_not_nil(result.python)
            assert.are.equal(0, #result.python)
        end)

        it('sets column to 0 for all chunk positions', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
            })
            local result = provider.extract_code_chunks(buf)
            assert.are.equal(0, result.python[1].range.from[2])
            assert.are.equal(0, result.python[1].range.to[2])
        end)

    end)


    describe('get_chunk_under_cursor', function()
        -- buffer layout used by most tests in this block:
        -- line 1: # %%      <- cell 1 delimiter
        -- line 2: x = 1     <- cell 1 content
        -- line 3: y = 2     <- cell 1 content (to[1]=3, blank trimmed)
        -- line 4:           <- blank (outside any cell range)
        -- line 5: # %%      <- cell 2 delimiter
        -- line 6: z = 3     <- cell 2 content

        before_each(function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
                'y = 2',
                '',
                '# %%',
                'z = 3',
            })
        end)

        it('finds a cell from a content line', function()
            local chunk = provider.get_chunk_under_cursor(2)
            assert.is_not_nil(chunk)
            assert.are.equal(1, chunk.range.from[1])
        end)

        it('finds a cell when cursor is on the # %% delimiter line', function()
            local chunk = provider.get_chunk_under_cursor(1)
            assert.is_not_nil(chunk)
            assert.are.equal(1, chunk.range.from[1])
        end)

        it('finds the correct cell for the second delimiter line', function()
            local chunk = provider.get_chunk_under_cursor(5)
            assert.is_not_nil(chunk)
            assert.are.equal(5, chunk.range.from[1])
        end)

        it('finds cell 1 for its last content line', function()
            local chunk = provider.get_chunk_under_cursor(3)
            assert.is_not_nil(chunk)
            assert.are.equal(1, chunk.range.from[1])
        end)

        it('returns nil for the blank line between cells', function()
            local chunk = provider.get_chunk_under_cursor(4)
            assert.is_nil(chunk)
        end)

        it('finds cell 2 for its content line', function()
            local chunk = provider.get_chunk_under_cursor(6)
            assert.is_not_nil(chunk)
            assert.are.equal(5, chunk.range.from[1])
        end)

        it('does not assign the blank line between cells to either cell', function()
            local chunk = provider.get_chunk_under_cursor(4)
            assert.is_nil(chunk)
        end)

        it('returns nil when no delimiters exist', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, { 'no delimiters here' })
            local chunk = provider.get_chunk_under_cursor(1)
            assert.is_nil(chunk)
        end)

    end)

end)
