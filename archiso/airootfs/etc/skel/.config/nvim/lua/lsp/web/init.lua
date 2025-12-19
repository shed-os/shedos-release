-- Web Development LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.web.core.html")
    helpers.safe_require("lsp.web.core.css")
    helpers.safe_setup("lsp.web.features.tailwind")
    helpers.safe_setup("lsp.web.features.emmet")
    helpers.safe_setup("lsp.web.ui.preview")
    helpers.safe_setup("lsp.web.utils.colors")

    vim.notify("Web LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "html", "css", "scss" },
    callback = function() M.setup() end,
    once = true,
})

return M
