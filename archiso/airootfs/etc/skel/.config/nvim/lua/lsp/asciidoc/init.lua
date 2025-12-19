-- Asciidoc LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.asciidoc.core.asciidoctor")
    helpers.safe_setup("lsp.asciidoc.features.preview")
    helpers.safe_setup("lsp.asciidoc.features.conversion")
    helpers.safe_setup("lsp.asciidoc.ui.render")
    helpers.safe_setup("lsp.asciidoc.utils.attributes")

    vim.notify("Asciidoc LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "asciidoc", "asciidoctor" },
    callback = function()
        M.setup()
    end,
    once = true,
})

return M
