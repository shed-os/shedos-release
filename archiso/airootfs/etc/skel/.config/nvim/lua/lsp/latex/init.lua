-- LaTeX LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.latex.core.texlab")
    helpers.safe_setup("lsp.latex.features.compilation")
    helpers.safe_setup("lsp.latex.features.bibliography")
    helpers.safe_setup("lsp.latex.features.preview")
    helpers.safe_setup("lsp.latex.ui.pdf")
    helpers.safe_setup("lsp.latex.utils.snippets")

    vim.notify("LaTeX LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "tex", "latex", "plaintex" },
    callback = function()
        M.setup()
    end,
    once = true,
})

return M
