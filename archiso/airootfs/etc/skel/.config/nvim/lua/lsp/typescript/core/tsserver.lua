-- TypeScript Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")

    -- Configure ESLint LSP for JavaScript/TypeScript linting
    lspconfig.eslint.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            -- Enable eslint code actions
            vim.api.nvim_create_autocmd("BufWritePre", {
                buffer = bufnr,
                command = "EslintFixAll",
            })
        end,
        settings = {
            workingDirectory = { mode = "auto" },
        },
    })

    lspconfig.tsserver.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            -- Workaround for tsserver inlay hints race condition
            -- Disable inlay hints during insert mode to prevent "Invalid col" errors
            if vim.lsp.inlay_hint then
                -- Start with inlay hints enabled
                vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })

                -- Disable inlay hints when entering insert mode
                vim.api.nvim_create_autocmd("InsertEnter", {
                    buffer = bufnr,
                    callback = function()
                        if vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }) then
                            vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
                        end
                    end,
                })

                -- Re-enable inlay hints when leaving insert mode (with small delay)
                vim.api.nvim_create_autocmd("InsertLeave", {
                    buffer = bufnr,
                    callback = function()
                        vim.defer_fn(function()
                            if vim.api.nvim_buf_is_valid(bufnr) then
                                vim.lsp.inlay_hint.enable(true, { bufnr = bufnr })
                            end
                        end, 100) -- 100ms delay to let buffer stabilize
                    end,
                })
            end

            vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr })
            vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = bufnr })

            -- Toggle inlay hints with <leader>th
            vim.keymap.set("n", "<leader>th", function()
                vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled({ bufnr = bufnr }), { bufnr = bufnr })
            end, { buffer = bufnr, desc = "Toggle Inlay Hints" })
        end,
        settings = {
            typescript = {
                inlayHints = {
                    includeInlayParameterNameHints = "all",
                    includeInlayParameterNameHintsWhenArgumentMatchesName = true,
                    includeInlayFunctionParameterTypeHints = true,
                    includeInlayVariableTypeHints = true,
                    includeInlayVariableTypeHintsWhenTypeMatchesName = true,
                    includeInlayPropertyDeclarationTypeHints = true,
                    includeInlayFunctionLikeReturnTypeHints = true,
                    includeInlayEnumMemberValueHints = true,
                },
            },
            javascript = {
                inlayHints = {
                    includeInlayParameterNameHints = "all",
                    includeInlayParameterNameHintsWhenArgumentMatchesName = true,
                    includeInlayFunctionParameterTypeHints = true,
                    includeInlayVariableTypeHints = true,
                    includeInlayVariableTypeHintsWhenTypeMatchesName = true,
                    includeInlayPropertyDeclarationTypeHints = true,
                    includeInlayFunctionLikeReturnTypeHints = true,
                    includeInlayEnumMemberValueHints = true,
                },
            },
        },
    })
end

M.setup()
return M
