-- Data Formats LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.data.core.yamlls")
    helpers.safe_require("lsp.data.core.jsonls")
    helpers.safe_require("lsp.data.core.lemminx")
    helpers.safe_setup("lsp.data.features.schemas")
    helpers.safe_setup("lsp.data.features.github-actions") -- GitHub Actions support
    helpers.safe_setup("lsp.data.features.azure-pipelines") -- Azure Pipelines support
    helpers.safe_setup("lsp.data.ui.preview")
    helpers.safe_setup("lsp.data.utils.validator")

    vim.notify("Data Formats LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "yaml", "json", "xml" },
    callback = function() M.setup() end,
    once = true,
})

return M
