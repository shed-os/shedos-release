-- Gopls Language Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    
    lspconfig.gopls.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            local opts = { buffer = bufnr, silent = true }
            
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
            vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
            vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)
            
            -- Go-specific
            vim.keymap.set("n", "<leader>gb", "<cmd>GoBuild<CR>", 
                vim.tbl_extend("force", opts, { desc = "Go build" }))
            vim.keymap.set("n", "<leader>gr", "<cmd>GoRun<CR>", 
                vim.tbl_extend("force", opts, { desc = "Go run" }))
            vim.keymap.set("n", "<leader>gt", "<cmd>GoTest<CR>", 
                vim.tbl_extend("force", opts, { desc = "Go test" }))
            vim.keymap.set("n", "<leader>gf", "<cmd>GoFmt<CR>", 
                vim.tbl_extend("force", opts, { desc = "Go format" }))
            vim.keymap.set("n", "<leader>gi", "<cmd>GoImports<CR>", 
                vim.tbl_extend("force", opts, { desc = "Organize imports" }))
            
            vim.notify("Gopls attached", vim.log.levels.INFO)
        end,
        settings = {
            gopls = {
                analyses = {
                    unusedparams = true,
                    shadow = true,
                },
                staticcheck = true,
                gofumpt = true,
                usePlaceholders = true,
                completeUnimported = true,
                matcher = "fuzzy",
                experimentalPostfixCompletions = true,
                hints = {
                    assignVariableTypes = true,
                    compositeLiteralFields = true,
                    compositeLiteralTypes = true,
                    constantValues = true,
                    functionTypeParameters = true,
                    parameterNames = true,
                    rangeVariableTypes = true,
                },
            },
        },
    })
end

M.setup()
return M
