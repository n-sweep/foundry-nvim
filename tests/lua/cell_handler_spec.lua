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
