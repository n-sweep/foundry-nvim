local buf = vim.api.nvim_create_buf(false, true)
local row = 16
local lines = {'hello', 'goodbye'}

vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

vim.api.nvim_open_win(buf, false, {
    relative = 'win',
    bufpos = { row - 1, 0 },
    width = vim.api.nvim_win_get_width(0),
    height = math.min(#lines, math.ceil(vim.api.nvim_win_get_height(0) / 2)),
    -- border = M.opts.border,
    title = 'hello'
})


--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--

--
--
--
--
--
--
--
--
--
--
--
--
--
--
--
--
--
--
--
--
