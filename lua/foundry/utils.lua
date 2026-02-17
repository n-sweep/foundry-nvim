local M = {}

--- Check if the current buffer is a Quarto document.
--- @return boolean is_quarto True if filetype is 'quarto'
function M.is_quarto()
    return vim.bo.filetype == 'quarto'
end

return M
