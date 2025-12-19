-- Markdown Formatting
local M = {}

function M.setup()
    -- Format with prettier or markdownlint
    vim.api.nvim_create_user_command("MarkdownFormat", function()
        vim.lsp.buf.format({ async = true })
    end, { desc = "Format markdown" })
end

M.setup()
return M
