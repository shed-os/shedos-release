-- Zig Language Server (ZLS) Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    
    lspconfig.zls.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            local opts = { buffer = bufnr, silent = true }
            
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
            vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, opts)
            vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, opts)
            
            -- Zig-specific
            vim.keymap.set("n", "<leader>zb", "<cmd>ZigBuild<CR>", 
                vim.tbl_extend("force", opts, { desc = "Zig build" }))
            vim.keymap.set("n", "<leader>zr", "<cmd>ZigRun<CR>", 
                vim.tbl_extend("force", opts, { desc = "Zig run" }))
            vim.keymap.set("n", "<leader>zt", "<cmd>ZigTest<CR>", 
                vim.tbl_extend("force", opts, { desc = "Zig test" }))
            
            vim.notify("ZLS attached", vim.log.levels.INFO)
        end,
        settings = {
            zls = {
                enable_autofix = true,
                enable_snippets = true,
                warn_style = true,
                enable_build_on_save = false,
                build_on_save_step = "check",
            },
        },
    })
end

M.setup()
return M
