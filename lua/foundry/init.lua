local bridge = require('foundry.ipy_bridge')
local cell_handler = require('foundry.cell_handler')

local M = {
    start = bridge.start,
    stop = bridge.stop,
    execute_cell = cell_handler.execute_cell,
    goto_next_cell = cell_handler.goto_next_cell,
    goto_prev_cell = cell_handler.goto_prev_cell,
}

bridge.set_result_handler(cell_handler.handle_execution_result)
cell_handler.set_executor(bridge.execute)


return M
