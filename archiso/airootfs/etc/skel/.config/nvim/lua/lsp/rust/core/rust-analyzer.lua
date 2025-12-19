-- Rust-Analyzer Language Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    
    lspconfig.rust_analyzer.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            local opts = { buffer = bufnr, silent = true }
            
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
            vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
            vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)
            
            -- Rust-specific
            vim.keymap.set("n", "<leader>rb", "<cmd>RustBuild<CR>", 
                vim.tbl_extend("force", opts, { desc = "Cargo build" }))
            vim.keymap.set("n", "<leader>rr", "<cmd>RustRun<CR>", 
                vim.tbl_extend("force", opts, { desc = "Cargo run" }))
            vim.keymap.set("n", "<leader>rt", "<cmd>RustTest<CR>", 
                vim.tbl_extend("force", opts, { desc = "Cargo test" }))
            vim.keymap.set("n", "<leader>rc", "<cmd>RustCheck<CR>", 
                vim.tbl_extend("force", opts, { desc = "Cargo check" }))
            vim.keymap.set("n", "<leader>rf", "<cmd>RustFmt<CR>", 
                vim.tbl_extend("force", opts, { desc = "Rust format" }))
            
            -- Rust-analyzer specific
            vim.keymap.set("n", "<leader>rh", function()
                vim.cmd("RustHoverActions")
            end, vim.tbl_extend("force", opts, { desc = "Hover actions" }))
            
            vim.keymap.set("n", "<leader>re", function()
                vim.cmd("RustExpandMacro")
            end, vim.tbl_extend("force", opts, { desc = "Expand macro" }))
            
            vim.notify("Rust-analyzer attached", vim.log.levels.INFO)
        end,
        settings = {
            ["rust-analyzer"] = {
                cargo = {
                    allFeatures = true,
                    loadOutDirsFromCheck = true,
                    runBuildScripts = true,
                },
                checkOnSave = {
                    command = "clippy",
                    allFeatures = true,
                },
                procMacro = {
                    enable = true,
                    ignored = {
                        ["async-trait"] = { "async_trait" },
                        ["napi-derive"] = { "napi" },
                        ["async-recursion"] = { "async_recursion" },
                    },
                },
                inlayHints = {
                    chainingHints = { enable = true },
                    closureReturnTypeHints = { enable = "always" },
                    lifetimeElisionHints = { enable = "always" },
                    parameterHints = { enable = true },
                },
                lens = {
                    enable = true,
                    run = { enable = true },
                    debug = { enable = true },
                    implementations = { enable = true },
                    references = {
                        adt = { enable = true },
                        enumVariant = { enable = true },
                        method = { enable = true },
                        trait = { enable = true },
                    },
                },
            },
        },
    })
end

M.setup()
return M
