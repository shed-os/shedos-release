-- Marksman Language Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    
    lspconfig.marksman.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            local opts = { buffer = bufnr, silent = true }
            
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
            vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
            vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
            
            -- Markdown-specific
            vim.keymap.set("n", "<leader>mp", "<cmd>MarkdownPreview<CR>", 
                vim.tbl_extend("force", opts, { desc = "Markdown preview" }))
            vim.keymap.set("n", "<leader>mt", "<cmd>MarkdownPreviewToggle<CR>", 
                vim.tbl_extend("force", opts, { desc = "Toggle preview" }))
        end,
    })
end

M.setup()
return M
