-- Go Formatter (gofmt/goimports)
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("GoFmt", function()
        vim.cmd("!gofmt -w %")
        vim.cmd("edit")
    end, { desc = "Format Go file" })
    
    vim.api.nvim_create_user_command("GoImports", function()
        vim.cmd("!goimports -w %")
        vim.cmd("edit")
    end, { desc = "Organize Go imports" })
    
    -- Auto-format on save
    vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.go",
        callback = function()
            vim.lsp.buf.format({ async = false })
        end,
    })
end

M.setup()
return M
