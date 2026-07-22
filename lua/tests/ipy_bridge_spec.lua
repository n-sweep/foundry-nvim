local core = require("foundry.core")
local bridge = require("foundry.ipy_bridge")

describe("IPython Bridge", function()
    it("reads a notebook", function()
        core.load_notebook('python/test.ipynb')
        assert.is_not_nil(core.cells)
        assert.is_true(#core.cell_order > 0)
    end)

    it("can start and stop a kernel", function()
        core.start_ipython()
        assert.is_true(bridge.handle > 0)
        core.stop_ipython()

        vim.wait(5000, function() return bridge.handle == 0 end, 100)
    end)
end)
