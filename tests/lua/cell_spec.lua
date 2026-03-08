describe('Cell', function()
    local Cell
    local ns
    local buf
    local opts

    before_each(function()
        package.loaded['foundry.cell'] = nil
        Cell = require('foundry.cell')
        ns = vim.api.nvim_create_namespace('test_cell_ns_' .. math.random(1e9))
        buf = vim.api.nvim_create_buf(false, true)
        vim.api.nvim_set_current_buf(buf)
        opts = { display_max_lines = nil }
    end)

    after_each(function()
        package.loaded['foundry.cell'] = nil
        vim.api.nvim_buf_delete(buf, { force = true })
    end)


    describe('_update_display', function()

        it('creates exactly two extmarks (not three)', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '```{python}',
                'x = 1',
                'y = 2',
                '```',
            })
            Cell:new(1, 3, 'python', ns, opts)
            local extmarks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
            assert.are.equal(2, #extmarks)
        end)

        it('places output extmark at end_row (0-indexed) for quarto', function()
            -- Cell:new(1, 4) → _update_display(0, 4)
            -- output extmark at row 4 (closing fence); virt_lines_above renders output above it
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '```{python}',
                'x = 1',
                'y = 2',
                'z = 3',
                '```',
            })
            local cell = Cell:new(1, 4, 'python', ns, opts)
            local em = vim.api.nvim_buf_get_extmark_by_id(0, ns, cell.output_id, { details = true })
            assert.are.equal(4, em[1])
        end)

        it('places output extmark at end_row for ipynb (on the blank line)', function()
            -- ipynb cell 1: to[1]=3 (last non-blank content), blank at line 4, # %% at line 5
            -- Cell:new(1, 3) → _update_display(0, 3): end_row=3 (0-indexed = blank line)
            -- output extmark at row 3 (blank line); virt_lines_above renders output above it,
            -- i.e. between last content and blank line
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
                'y = 2',
                '',
                '# %%',
                'z = 3',
            })
            local cell = Cell:new(1, 3, 'python', ns, opts)
            local em = vim.api.nvim_buf_get_extmark_by_id(0, ns, cell.output_id, { details = true })
            assert.are.equal(3, em[1])
        end)



        it('output extmark uses virt_lines', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
            })
            local cell = Cell:new(1, 2, 'python', ns, opts)
            local em = vim.api.nvim_buf_get_extmark_by_id(0, ns, cell.output_id, { details = true })
            assert.is_not_nil(em[3].virt_lines)
            assert.is_true(#em[3].virt_lines > 0)
        end)

        it('output extmark has virt_lines_above set', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
            })
            local cell = Cell:new(1, 2, 'python', ns, opts)
            local em = vim.api.nvim_buf_get_extmark_by_id(0, ns, cell.output_id, { details = true })
            assert.is_true(em[3].virt_lines_above)
        end)

    end)


    describe('get_pos', function()

        it('returns 0-indexed start and end rows from the main extmark', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '```{python}',
                'x = 1',
                '```',
            })
            local cell = Cell:new(1, 2, 'python', ns, opts)
            local start_row, end_row = cell:get_pos()
            assert.are.equal(0, start_row)
            assert.are.equal(2, end_row)
        end)

        it('end_row reflects the main extmark end_row, unaffected by output extmark position', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
                'y = 2',
                '# %%',
            })
            local cell = Cell:new(1, 3, 'python', ns, opts)
            local _, end_row = cell:get_pos()
            -- end_row should be 3 (the original to[1] value used as 0-indexed),
            -- not 2 (the output extmark position)
            assert.are.equal(3, end_row)
        end)

    end)


    describe('Cell:delete', function()

        it('removes all extmarks from the namespace', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
            })
            local cell = Cell:new(1, 2, 'python', ns, opts)
            cell:delete()
            local extmarks = vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, {})
            assert.are.equal(0, #extmarks)
        end)

        it('sets status to deleted', function()
            vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
                '# %%',
                'x = 1',
            })
            local cell = Cell:new(1, 2, 'python', ns, opts)
            cell:delete()
            assert.are.equal('deleted', cell.status)
        end)

    end)

end)
