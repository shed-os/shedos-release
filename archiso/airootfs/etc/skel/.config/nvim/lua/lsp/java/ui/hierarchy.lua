-- Class Hierarchy View
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("JavaHierarchy", function()
        vim.lsp.buf.type_hierarchy()
    end, { desc = "Show Java class hierarchy" })
end

return M
