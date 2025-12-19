-- Clangd Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    
    lspconfig.clangd.setup({
        cmd = {
            "clangd",
            "--background-index",
            "--clang-tidy",
            "--header-insertion=iwyu",
            "--completion-style=detailed",
            "--function-arg-placeholders=true",
        },
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr })
            vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
            vim.keymap.set("n", "<leader>ch", ":ClangdSwitchSourceHeader<CR>", { buffer = bufnr })
        end,
    })
end

M.setup()
return M
