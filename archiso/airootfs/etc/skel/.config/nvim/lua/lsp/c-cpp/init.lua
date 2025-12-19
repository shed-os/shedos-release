-- C/C++ LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    -- Load core LSP
    helpers.safe_require("lsp.c-cpp.core.clangd")

    -- Load features
    helpers.safe_setup("lsp.c-cpp.features.cmake")
    helpers.safe_setup("lsp.c-cpp.features.debugging")

    -- Load UI (DAP might not be loaded yet)
    helpers.safe_setup("lsp.c-cpp.ui.dap")

    -- Load utilities
    helpers.safe_setup("lsp.c-cpp.utils.build")

    vim.notify("C/C++ LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "c", "cpp" },
    callback = function() M.setup() end,
    once = true,
})

return M
