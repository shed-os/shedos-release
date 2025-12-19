-- Zig LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.zig.core.zls")
    helpers.safe_setup("lsp.zig.features.build")
    helpers.safe_setup("lsp.zig.features.testing")
    helpers.safe_setup("lsp.zig.ui.dap")
    helpers.safe_setup("lsp.zig.utils.formatter")

    vim.notify("Zig LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "zig",
    callback = function()
        M.setup()
    end,
    once = true,
})

return M
