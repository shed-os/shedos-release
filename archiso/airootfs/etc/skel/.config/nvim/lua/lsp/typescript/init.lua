-- TypeScript/JavaScript LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    -- Load core LSP
    helpers.safe_require("lsp.typescript.core.tsserver")

    -- Load features
    helpers.safe_setup("lsp.typescript.features.react")
    helpers.safe_setup("lsp.typescript.features.node")

    -- Load UI (DAP might not be loaded yet)
    helpers.safe_setup("lsp.typescript.ui.dap")

    -- Load utilities
    helpers.safe_setup("lsp.typescript.utils.package")

    vim.notify("TypeScript LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "javascript", "typescript", "javascriptreact", "typescriptreact" },
    callback = function() M.setup() end,
    once = true,
})

return M
