describe("execute_cell cursor position", function()
    local cell_handler
    local buf
    local executed_cell_ids
    local executed_codes

    before_each(function()
        package.loaded['foundry.logging'] = {
            get_logger = function()
                return { info = function() end, warn = function() end, error = function() end }
            end
        }

        executed_cell_ids = {}
        executed_codes = {}
        package.loaded['foundry.ipy_bridge'] = {
            setup = function() end,
            start = function() return true end,
            execute = function(cell_id, code)
                table.insert(executed_cell_ids, cell_id)
                table.insert(executed_codes, code)
            end
        }

        buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '```{python}',
            'x = 1',
            'y = 2',
            'z = 3',
            '```',
        })
        vim.api.nvim_set_current_buf(buf)
        vim.bo.filetype = 'quarto'

        package.loaded['otter.keeper'] = {
            extract_code_chunks = function()
                return {
                    python = {
                        { range = { from = {1, 0}, to = {4, 0} }, lang = 'python' }
                    }
                }
            end
        }

        package.loaded['foundry.cell_handler'] = nil
        cell_handler = require('foundry.cell_handler')
        cell_handler.setup('/plugin', { display_max_lines = nil, border = 'single' })
    end)

    after_each(function()
        package.loaded['foundry.logging'] = nil
        package.loaded['foundry.ipy_bridge'] = nil
        package.loaded['foundry.cell_handler'] = nil
        package.loaded['otter.keeper'] = nil
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    local function execute_from_row(row)
        vim.api.nvim_win_set_cursor(0, {row, 0})
        cell_handler.execute_cell()
        return executed_cell_ids[#executed_cell_ids], executed_codes[#executed_codes]
    end

    local function simulate_run()
        local cell_id = next(cell_handler.cells)
        cell_handler.handle_ipy_message({
            cell_id = cell_id,
            status = 'ok',
            execution_count = 1,
            messages = {{ output_type = 'stream', text = 'hello\n' }}
        })
    end

    it("finds the cell from any row before first run", function()
        local id1, code1 = execute_from_row(1)
        local id2, code2 = execute_from_row(2)
        local id3, code3 = execute_from_row(3)
        assert.is_not_nil(id1)
        assert.are.equal(id1, id2)
        assert.are.equal(id1, id3)
        assert.are.equal('x = 1\ny = 2\nz = 3', code1)
        assert.are.equal('x = 1\ny = 2\nz = 3', code2)
        assert.are.equal('x = 1\ny = 2\nz = 3', code3)
    end)

    it("finds the same cell from any row after a run", function()
        execute_from_row(1)
        simulate_run()
        executed_cell_ids = {}
        executed_codes = {}

        local id1, code1 = execute_from_row(1)
        local id2, code2 = execute_from_row(2)
        local id3, code3 = execute_from_row(3)
        assert.is_not_nil(id1)
        assert.are.equal(id1, id2)
        assert.are.equal(id1, id3)
        assert.are.equal('x = 1\ny = 2\nz = 3', code1)
        assert.are.equal('x = 1\ny = 2\nz = 3', code2)
        assert.are.equal('x = 1\ny = 2\nz = 3', code3)
    end)

    it("reuses existing cell after editing content and adding lines", function()
        -- start with a single-line cell
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '```{python}',
            'x = 1',
            '```',
        })
        package.loaded['otter.keeper'] = {
            extract_code_chunks = function()
                return {
                    python = {
                        { range = { from = {1, 0}, to = {2, 0} }, lang = 'python' }
                    }
                }
            end
        }
        package.loaded['foundry.cell_handler'] = nil
        cell_handler = require('foundry.cell_handler')
        cell_handler.setup('/plugin', { display_max_lines = nil, border = 'single' })

        execute_from_row(1)
        local original_id = executed_cell_ids[1]
        simulate_run()
        executed_cell_ids = {}
        executed_codes = {}

        -- edit the existing line and add two new lines before the closing fence,
        -- one at a time with keeper mock and prune_cells updates to simulate TextChanged
        vim.api.nvim_buf_set_lines(buf, 1, 2, false, {'inits = x'})
        cell_handler.keeper = { extract_code_chunks = function() return { python = { { range = { from = {1, 0}, to = {2, 0} }, lang = 'python' } } } end }
        cell_handler.prune_cells()

        vim.api.nvim_buf_set_lines(buf, 2, 2, false, {'mask = inits == "JP"'})
        cell_handler.keeper = { extract_code_chunks = function() return { python = { { range = { from = {1, 0}, to = {3, 0} }, lang = 'python' } } } end }
        cell_handler.prune_cells()

        vim.api.nvim_buf_set_lines(buf, 3, 3, false, {'customers_mask'})
        cell_handler.keeper = { extract_code_chunks = function() return { python = { { range = { from = {1, 0}, to = {4, 0} }, lang = 'python' } } } end }
        cell_handler.prune_cells()

        -- run normally from each row including the newly added lines
        local id1, code1 = execute_from_row(1)
        local id2, code2 = execute_from_row(2)
        local id3, code3 = execute_from_row(3)
        local id4, code4 = execute_from_row(4)
        assert.are.equal(original_id, id1)
        assert.are.equal(original_id, id2)
        assert.are.equal(original_id, id3)
        assert.are.equal(original_id, id4)
        assert.are.equal('inits = x\nmask = inits == "JP"\ncustomers_mask', code1)
        assert.are.equal('inits = x\nmask = inits == "JP"\ncustomers_mask', code2)
        assert.are.equal('inits = x\nmask = inits == "JP"\ncustomers_mask', code3)
        assert.are.equal('inits = x\nmask = inits == "JP"\ncustomers_mask', code4)

        -- visual selection of a single new line
        executed_cell_ids = {}
        executed_codes = {}
        vim.api.nvim_win_set_cursor(0, {3, 0})
        vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('V', true, false, true), 'x', false)
        cell_handler.execute_cell()
        assert.are.equal(original_id, executed_cell_ids[1])
        assert.are.equal('mask = inits == "JP"', executed_codes[1])
    end)
end)


describe("cell_handler", function()
    local cell_handler
    local mock_cell
    local cell_update_calls

    before_each(function()
        -- Mock logging
        package.loaded['foundry.logging'] = {
            get_logger = function()
                return {
                    info = function() end,
                    warn = function() end,
                    error = function() end
                }
            end
        }

        -- Mock ipy_bridge
        package.loaded['foundry.ipy_bridge'] = {
            setup = function() end,
            start = function() return true end,
            execute = function() end
        }

        -- Mock Cell
        cell_update_calls = {}
        mock_cell = {
            id = 1,
            update = function(_, status, exec, lines)
                table.insert(cell_update_calls, {
                    status = status,
                    exec = exec,
                    lines = lines
                })
            end
        }
        -- Load cell_handler fresh
        package.loaded['foundry.cell_handler'] = nil
        cell_handler = require('foundry.cell_handler')

        -- Inject mock cell into handler
        cell_handler.cells = { [1] = mock_cell }
    end)

    after_each(function()
        package.loaded['foundry.logging'] = nil
        package.loaded['foundry.ipy_bridge'] = nil
        package.loaded['foundry.cell_handler'] = nil
    end)

    describe("handle_ipy_message", function()
        it("handles stream output", function()
            local msg = {
                cell_id = 1,
                status = "ok",
                execution_count = 5,
                messages = {
                    { output_type = "stream", name = "stdout", text = "hello world\n" }
                }
            }

            cell_handler.handle_ipy_message(msg)

            assert.are.equal(1, #cell_update_calls)
            local call = cell_update_calls[1]
            assert.are.equal("Done", call.status)
            assert.are.equal(5, call.exec)
            assert.are.equal(1, #call.lines)
            assert.are.equal("hello world", call.lines[1])
        end)

        it("handles execute_result output", function()
            local msg = {
                cell_id = 1,
                status = "ok",
                execution_count = 3,
                messages = {
                    {
                        output_type = "execute_result",
                        data = { ["text/plain"] = "42" },
                        execution_count = 3
                    }
                }
            }

            cell_handler.handle_ipy_message(msg)

            assert.are.equal(1, #cell_update_calls)
            local call = cell_update_calls[1]
            assert.are.equal("Done", call.status)
            assert.are.equal(3, call.exec)
            assert.are.equal(1, #call.lines)
            assert.are.equal("42", call.lines[1])
        end)

        it("handles error output", function()
            local msg = {
                cell_id = 1,
                status = "error",
                execution_count = 2,
                messages = {
                    {
                        output_type = "error",
                        ename = "ValueError",
                        evalue = "test error",
                        traceback = {
                            ["text/plain"] = {
                                "Traceback (most recent call last):",
                                "  File \"<stdin>\", line 1, in <module>",
                                "ValueError: test error"
                            },
                            ["text/ANSI"] = {
                                "Traceback (most recent call last):",
                                "  File \"<stdin>\", line 1, in <module>",
                                "ValueError: test error"
                            }
                        }
                    }
                }
            }

            cell_handler.handle_ipy_message(msg)

            assert.are.equal(1, #cell_update_calls)
            local call = cell_update_calls[1]
            assert.are.equal("Error", call.status)
            assert.are.equal("E", call.exec)
            assert.are.equal(3, #call.lines)
            assert.is_true(call.lines[3]:match("ValueError: test error") ~= nil)
        end)

        it("handles multiple messages (stream + execute_result)", function()
            local msg = {
                cell_id = 1,
                status = "ok",
                execution_count = 7,
                messages = {
                    { output_type = "stream", name = "stdout", text = "calculating...\n" },
                    {
                        output_type = "execute_result",
                        data = { ["text/plain"] = "100" },
                        execution_count = 7
                    }
                }
            }

            cell_handler.handle_ipy_message(msg)

            assert.are.equal(1, #cell_update_calls)
            local call = cell_update_calls[1]
            assert.are.equal("Done", call.status)
            assert.are.equal(7, call.exec)
            assert.are.equal(2, #call.lines)
            assert.are.equal("calculating...", call.lines[1])
            assert.are.equal("100", call.lines[2])
        end)

        it("handles empty execution (no output)", function()
            local msg = {
                cell_id = 1,
                status = "ok",
                execution_count = 4,
                messages = {}
            }

            cell_handler.handle_ipy_message(msg)

            assert.are.equal(1, #cell_update_calls)
            local call = cell_update_calls[1]
            assert.are.equal("Done", call.status)
            assert.are.equal(4, call.exec)
            assert.are.equal(0, #call.lines)
        end)

        it("handles shutdown_all message", function()
            local msg = {
                type = "shutdown_all"
            }

            -- Should not crash, just set flag
            cell_handler.handle_ipy_message(msg)
            assert.is_true(cell_handler.ipython_down)
        end)
    end)
end)


-- Regression test for the indexing bug: row from nvim_win_get_cursor is 1-indexed but
-- was being passed as 0-indexed to get_quarto_chunk_under_cursor, which compares against
-- 1-indexed otter chunk positions. This caused cells to silently not be found when the
-- cursor was on the opening fence line of a cell that had no extmark yet.
describe("cell_handler chunk lookup indexing fix", function()
    local cell_handler
    local buf
    local executed_cell_ids
    local executed_codes

    before_each(function()
        package.loaded['foundry.logging'] = {
            get_logger = function()
                return { info = function() end, warn = function() end, error = function() end }
            end
        }

        executed_cell_ids = {}
        executed_codes = {}
        package.loaded['foundry.ipy_bridge'] = {
            setup = function() end,
            start = function() return true end,
            execute = function(cell_id, code)
                table.insert(executed_cell_ids, cell_id)
                table.insert(executed_codes, code)
            end
        }

        -- Start with an empty buffer so setup() creates no cells (no extmarks)
        buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_set_current_buf(buf)
        vim.bo.filetype = 'quarto'

        package.loaded['otter.keeper'] = {
            extract_code_chunks = function() return {} end
        }

        package.loaded['foundry.cell_handler'] = nil
        cell_handler = require('foundry.cell_handler')
        cell_handler.setup('/plugin', { display_max_lines = nil, border = 'single' })
    end)

    after_each(function()
        package.loaded['foundry.logging'] = nil
        package.loaded['foundry.ipy_bridge'] = nil
        package.loaded['foundry.cell_handler'] = nil
        package.loaded['otter.keeper'] = nil
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    it("finds a cell when cursor is on the opening fence line with no extmark", function()
        -- Add a cell to the buffer after setup (so no extmark exists for it yet)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '```{python}',
            'x = 1',
            '```',
        })
        -- Update chunk_provider so it finds this new cell
        cell_handler.chunk_provider = {
            extract_code_chunks = function()
                return { python = { { range = { from = {1, 0}, to = {2, 0} }, lang = 'python' } } }
            end
        }

        -- Cursor on the opening fence line (line 1, 1-indexed)
        vim.api.nvim_win_set_cursor(0, {1, 0})
        cell_handler.execute_cell()

        -- Without the fix, row=0 is compared against from[1]=1 and 0>=1 is false,
        -- so no cell is found. With the fix, row=1 >= from[1]=1, cell is found.
        assert.are.equal(1, #executed_cell_ids)
        assert.are.equal('x = 1', executed_codes[1])
    end)

    it("finds a cell when cursor is on the fence of a cell not at line 1", function()
        -- Two cells; cursor on the opening fence of the second (line 4)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '```{python}',
            'x = 1',
            '```',
            '```{python}',
            'y = 2',
            '```',
        })
        cell_handler.chunk_provider = {
            extract_code_chunks = function()
                return { python = {
                    { range = { from = {1, 0}, to = {2, 0} }, lang = 'python' },
                    { range = { from = {4, 0}, to = {5, 0} }, lang = 'python' },
                }}
            end
        }

        -- Cursor on the opening fence of the second cell (line 4)
        vim.api.nvim_win_set_cursor(0, {4, 0})
        cell_handler.execute_cell()

        assert.are.equal(1, #executed_cell_ids)
        assert.are.equal('y = 2', executed_codes[1])
    end)
end)


describe("cell_handler with ipynb (python filetype)", function()
    local cell_handler
    local buf
    local executed_cell_ids
    local executed_codes

    -- buffer layout:
    -- line 1: # %%      <- cell 1 delimiter
    -- line 2: x = 1     <- cell 1 content
    -- line 3: y = 2     <- cell 1 content
    -- line 4: # %%      <- cell 2 delimiter
    -- line 5: z = 3     <- cell 2 content

    before_each(function()
        package.loaded['foundry.logging'] = {
            get_logger = function()
                return { info = function() end, warn = function() end, error = function() end }
            end
        }

        executed_cell_ids = {}
        executed_codes = {}
        package.loaded['foundry.ipy_bridge'] = {
            setup = function() end,
            start = function() return true end,
            execute = function(cell_id, code)
                table.insert(executed_cell_ids, cell_id)
                table.insert(executed_codes, code)
            end
        }

        buf = vim.api.nvim_create_buf(true, false)
        vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
            '# %%',
            'x = 1',
            'y = 2',
            '# %%',
            'z = 3',
        })
        vim.api.nvim_set_current_buf(buf)
        vim.bo.filetype = 'python'

        -- otter.keeper must be present at module load time even for ipynb mode
        package.loaded['otter.keeper'] = {
            extract_code_chunks = function() return {} end
        }

        -- ipynb_provider mock returning chunks that match the buffer above:
        --   cell 1: from[1]=1 (# %% at line 1), to[1]=3 (last content line)
        --   cell 2: from[1]=4 (# %% at line 4), to[1]=5 (last content line / EOF)
        -- getline(from[1]+1, to[1]) gives the code content, skipping the # %% line.
        package.loaded['foundry.ipynb_provider'] = {
            extract_code_chunks = function()
                return { python = {
                    { range = { from = {1, 0}, to = {3, 0} }, lang = 'python' },
                    { range = { from = {4, 0}, to = {5, 0} }, lang = 'python' },
                }}
            end
        }

        package.loaded['foundry.cell_handler'] = nil
        cell_handler = require('foundry.cell_handler')
        cell_handler.setup('/plugin', { display_max_lines = nil, border = 'single' })
    end)

    after_each(function()
        package.loaded['foundry.logging'] = nil
        package.loaded['foundry.ipy_bridge'] = nil
        package.loaded['foundry.cell_handler'] = nil
        package.loaded['otter.keeper'] = nil
        package.loaded['foundry.ipynb_provider'] = nil
        vim.api.nvim_buf_delete(buf, { force = true })
    end)

    local function execute_from_row(row)
        vim.api.nvim_win_set_cursor(0, {row, 0})
        cell_handler.execute_cell()
        return executed_cell_ids[#executed_cell_ids], executed_codes[#executed_codes]
    end

    it("uses ipynb_provider (not otter) for chunk detection", function()
        local otter_called = false
        cell_handler.keeper = {
            extract_code_chunks = function() otter_called = true; return {} end
        }
        execute_from_row(2)
        assert.is_false(otter_called)
    end)

    it("finds and executes cell 1 from a content line", function()
        local id, code = execute_from_row(2)
        assert.is_not_nil(id)
        assert.are.equal('x = 1\ny = 2', code)
    end)

    it("finds and executes cell 1 from its last content line", function()
        local id, code = execute_from_row(3)
        assert.is_not_nil(id)
        assert.are.equal('x = 1\ny = 2', code)
    end)

    it("finds and executes cell 2 from its content line", function()
        local id, code = execute_from_row(5)
        assert.is_not_nil(id)
        assert.are.equal('z = 3', code)
    end)

    it("finds and executes cell 1 from its # %% delimiter line", function()
        local id, code = execute_from_row(1)
        assert.is_not_nil(id)
        assert.are.equal('x = 1\ny = 2', code)
    end)

    it("code does not include the # %% delimiter line", function()
        local _, code = execute_from_row(2)
        assert.is_nil(code:match('^# %%%%'))
    end)

    it("cells 1 and 2 are distinct", function()
        local id1 = execute_from_row(2)
        local id2 = execute_from_row(5)
        assert.is_not_nil(id1)
        assert.is_not_nil(id2)
        assert.are_not.equal(id1, id2)
    end)

    it("re-executing a cell reuses the same cell id", function()
        local id1 = execute_from_row(2)
        executed_cell_ids = {}
        local id2 = execute_from_row(2)
        assert.are.equal(id1, id2)
    end)
end)
