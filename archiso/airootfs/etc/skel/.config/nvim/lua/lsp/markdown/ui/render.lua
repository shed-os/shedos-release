-- Markdown Rendering
local M = {}

function M.setup()
    -- Enable concealment for markdown
    vim.opt_local.conceallevel = 2
end

M.setup()
return M
