-- SQL LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.sql.core.sqls")
    helpers.safe_setup("lsp.sql.features.postgresql")
    helpers.safe_setup("lsp.sql.features.mysql")
    helpers.safe_setup("lsp.sql.ui.query")
    helpers.safe_setup("lsp.sql.utils.formatter")

    vim.notify("SQL LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "sql",
    callback = function() M.setup() end,
    once = true,
})

return M
