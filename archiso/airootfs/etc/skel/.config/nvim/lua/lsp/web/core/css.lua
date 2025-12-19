-- CSS LSP Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    lspconfig.cssls.setup({
        capabilities = require("lsp.utils").get_capabilities(),
    })
end

M.setup()
return M
