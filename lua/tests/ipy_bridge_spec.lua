describe("IPython Bridge", function()
    M = require("foundry")

    it("reads a notebook", function()
        local result = M.load('python/test.ipynb')
        assert.is_not_nil(result)
    end)

    it("can start and stop a kernel", function()
        M.start()
        assert.is_true(M.handle > 0)
        M.stop()

        -- wait until job complete or 5 seconds
        vim.wait(5000, function() return M.handle == 0 end, 100)

    end)

end)
