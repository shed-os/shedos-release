-- Java Refactoring Support
local M = {}

function M.setup()
    -- Refactoring keymaps are set up in jdtls.lua on_attach
    vim.api.nvim_create_user_command("JavaRefactor", function()
        vim.lsp.buf.code_action()
    end, { desc = "Java refactoring menu" })
end

return M
