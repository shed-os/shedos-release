-- Markdown LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.markdown.core.marksman")
    helpers.safe_setup("lsp.markdown.features.preview")
    helpers.safe_setup("lsp.markdown.features.formatting")
    helpers.safe_setup("lsp.markdown.ui.render")
    helpers.safe_setup("lsp.markdown.utils.links")

    vim.notify("Markdown LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "markdown",
    callback = function()
        M.setup()
    end,
    once = true,
})

return M
