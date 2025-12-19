-- TeXLab Language Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    
    lspconfig.texlab.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            local opts = { buffer = bufnr, silent = true }
            
            -- Standard LSP keymaps
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, opts)
            vim.keymap.set("n", "K", vim.lsp.buf.hover, opts)
            vim.keymap.set("n", "gr", vim.lsp.buf.references, opts)
            
            -- LaTeX-specific keymaps
            vim.keymap.set("n", "<leader>lb", "<cmd>TexlabBuild<CR>", 
                vim.tbl_extend("force", opts, { desc = "Build LaTeX" }))
            vim.keymap.set("n", "<leader>lv", "<cmd>TexlabForward<CR>", 
                vim.tbl_extend("force", opts, { desc = "Forward search" }))
            vim.keymap.set("n", "<leader>lc", "<cmd>TexlabClean<CR>", 
                vim.tbl_extend("force", opts, { desc = "Clean auxiliary files" }))
            
            vim.notify("TeXLab LSP attached", vim.log.levels.INFO)
        end,
        settings = {
            texlab = {
                -- Build configuration
                build = {
                    executable = "latexmk",
                    args = {
                        "-pdf",
                        "-interaction=nonstopmode",
                        "-synctex=1",
                        "%f"
                    },
                    onSave = true,
                    forwardSearchAfter = false,
                },
                -- Forward search (PDF viewer integration)
                forwardSearch = {
                    executable = "zathura",  -- or "evince", "okular", "skim"
                    args = { "--synctex-forward", "%l:1:%f", "%p" },
                },
                -- Completion
                completion = {
                    matcher = "fuzzy",
                },
                -- Diagnostics
                diagnostics = {
                    delay = 300,
                },
                -- Formatting
                formatterLineLength = 120,
                -- LaTeX formatter
                latexFormatter = "latexindent",
                latexindent = {
                    modifyLineBreaks = true,
                },
            },
        },
    })
end

M.setup()
return M
