-- Rust LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    -- Load core LSP
    helpers.safe_require("lsp.rust.core.rust-analyzer")

    -- Load features
    helpers.safe_setup("lsp.rust.features.cargo")
    helpers.safe_setup("lsp.rust.features.testing")

    -- Load UI (DAP might not be loaded yet)
    helpers.safe_setup("lsp.rust.ui.dap")

    -- Load utilities
    helpers.safe_setup("lsp.rust.utils.crates")

    vim.notify("Rust LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = "rust",
    callback = function()
        M.setup()
    end,
    once = true,
})

return M
