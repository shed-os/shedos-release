-- Go LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.go.core.gopls")
    helpers.safe_setup("lsp.go.features.testing")
    helpers.safe_setup("lsp.go.features.modules")
    helpers.safe_setup("lsp.go.ui.dap")
    helpers.safe_setup("lsp.go.utils.formatter")

    vim.notify("Go LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "go",
    callback = function()
        M.setup()
    end,
    once = true,
})

return M
