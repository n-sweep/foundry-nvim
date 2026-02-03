describe("ipy_bridge", function()
    local ipy_bridge
    local mock_handler
    local original_jobstart
    local original_chansend
    local original_notify

    before_each(function()
        -- Mock logging to suppress log output during tests
        package.loaded['foundry.logging'] = {
            get_logger = function()
                return { info = function() end, warn = function() end, error = function() end }
            end
        }

        -- Save original vim functions to restore after each test
        original_jobstart = vim.fn.jobstart
        original_chansend = vim.fn.chansend
        original_notify = vim.notify

        -- Mock vim functions with default success behavior
        vim.fn.jobstart = function() return 1 end
        vim.fn.chansend = function() return 1 end

        mock_handler = { handle_ipy_message = function() end }

        -- Reload module fresh for each test
        package.loaded['foundry.ipy_bridge'] = nil
        ipy_bridge = require('foundry.ipy_bridge')
        ipy_bridge.setup(mock_handler, '/plugin')
    end)

    after_each(function()
        vim.fn.jobstart = original_jobstart
        vim.fn.chansend = original_chansend
        vim.notify = original_notify
        package.loaded['foundry.logging'] = nil
        package.loaded['foundry.ipy_bridge'] = nil
    end)

    it("manages subprocess lifecycle", function()
        -- Start subprocess successfully
        vim.fn.jobstart = function() return 42 end
        assert.is_true(ipy_bridge.start())

        -- Refuse to start when already running
        assert.is_false(ipy_bridge.start())
    end)

    it("handles jobstart failure", function()
        -- jobstart returns 0 or negative on failure
        vim.fn.jobstart = function() return 0 end
        assert.is_false(ipy_bridge.start())
    end)

    it("adds metadata to messages", function()
        vim.fn.jobstart = function() return 5 end
        ipy_bridge.start()

        -- Capture messages sent via chansend
        local sent
        vim.fn.chansend = function(_, data) sent = data; return 1 end

        -- Execute code and verify metadata with default buffer
        ipy_bridge.execute(100, 'x = 1')
        local msg = vim.fn.json_decode(sent:sub(1, -2))
        assert.is_not_nil(msg.meta)
        assert.are.equal(vim.fn.getpid(), msg.meta.pid)
        assert.are.equal(vim.api.nvim_get_current_buf(), msg.meta.buf)
        assert.are.equal(vim.api.nvim_buf_get_name(msg.meta.buf), msg.meta.file)
        assert.are.equal('\n', sent:sub(-1))

        -- Mock buffer functions to test explicit buffer parameter
        local original_get_buf = vim.api.nvim_get_current_buf
        local original_get_name = vim.api.nvim_buf_get_name
        vim.api.nvim_get_current_buf = function() return 1 end
        vim.api.nvim_buf_get_name = function(buf) return '/file' .. buf .. '.ipynb' end

        -- Verify explicit buffer parameter is used in metadata
        ipy_bridge.restart_kernel(99)
        msg = vim.fn.json_decode(sent:sub(1, -2))
        assert.is_not_nil(msg.meta)
        assert.are.equal(vim.fn.getpid(), msg.meta.pid)
        assert.are.equal(99, msg.meta.buf)
        assert.are.equal('/file99.ipynb', msg.meta.file)

        vim.api.nvim_get_current_buf = original_get_buf
        vim.api.nvim_buf_get_name = original_get_name
    end)

    it("handles execute errors", function()
        -- Capture error messages sent to handler
        local result
        mock_handler.handle_ipy_message = function(data) result = data end
        ipy_bridge.setup(mock_handler, '/plugin')

        -- Error when subprocess not running
        ipy_bridge.execute(200, 'x = 1')
        assert.are.equal(200, result.cell_id)
        assert.are.equal('error', result.status)
        assert.are.equal('IPython subprocess not running', result.messages[1].text)

        -- Error when chansend fails
        vim.fn.jobstart = function() return 5 end
        ipy_bridge.start()
        vim.fn.chansend = function() return 0 end

        ipy_bridge.execute(201, 'y = 2')
        assert.are.equal(201, result.cell_id)
        assert.are.equal('Failed to send execution request', result.messages[1].text)
    end)

    it("routes subprocess responses", function()
        -- Capture on_stdout callback
        local on_stdout
        vim.fn.jobstart = function(_, opts) on_stdout = opts.on_stdout; return 5 end
        ipy_bridge.start()

        local result
        mock_handler.handle_ipy_message = function(data) result = data end
        ipy_bridge.setup(mock_handler, '/plugin')

        -- Valid JSON gets routed to handler
        on_stdout(nil, {vim.fn.json_encode({cell_id = 300, status = 'ok'})}, nil)
        assert.are.equal(300, result.cell_id)
        assert.are.equal('ok', result.status)

        -- Invalid JSON is ignored (doesn't crash)
        result = nil
        on_stdout(nil, {'invalid json'}, nil)
        assert.is_nil(result)
    end)

    it("cleans up on subprocess exit", function()
        -- Capture on_exit callback and track start calls
        local on_exit
        local start_count = 0
        vim.fn.jobstart = function(_, opts)
            start_count = start_count + 1
            if start_count == 1 then
                on_exit = opts.on_exit
            end
            return start_count
        end
        ipy_bridge.start()

        -- Simulate clean exit
        on_exit(nil, 0, nil)

        -- Verify handle was cleared by successfully starting again
        assert.is_true(ipy_bridge.start())
    end)

    it("notifies on subprocess crash", function()
        -- Capture on_exit callback
        local on_exit
        vim.fn.jobstart = function(_, opts) on_exit = opts.on_exit; return 5 end
        ipy_bridge.start()

        -- Capture vim.notify call
        local notified = false
        vim.notify = function(msg, level)
            notified = msg:find('exit code: 1') and level == vim.log.levels.ERROR
        end

        -- Simulate error exit
        on_exit(nil, 1, nil)
        assert.is_true(notified)
    end)
end)
