-- Kotlin LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    -- Note: kotlin_language_server uses Java 21 from mise (not system Java 25)
    -- See: lsp.kotlin.core.lsp for configuration

    -- Load core LSP (configured with Java 21)
    helpers.safe_require("lsp.kotlin.core.lsp")

    -- Load features with safe setup
    helpers.safe_setup("lsp.kotlin.features.android")
    helpers.safe_setup("lsp.kotlin.features.gradle")
    helpers.safe_setup("lsp.kotlin.features.coroutines")

    -- Load UI with safe setup (DAP might not be loaded yet)
    helpers.safe_setup("lsp.kotlin.ui.dap")

    -- Load utilities
    helpers.safe_setup("lsp.kotlin.utils.build")

    vim.notify("Kotlin LSP setup complete (using Java 21)", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "kotlin",
    callback = function() M.setup() end,
    once = true,
})

return M
