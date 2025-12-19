-- Javadoc Support
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("JavaDoc", function()
        vim.lsp.buf.hover()
    end, { desc = "Show Javadoc" })
end

return M
