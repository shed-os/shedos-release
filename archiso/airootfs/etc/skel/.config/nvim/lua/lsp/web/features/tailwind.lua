-- TailwindCSS Support
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    lspconfig.tailwindcss.setup({
        capabilities = require("lsp.utils").get_capabilities(),
    })
end

M.setup()
return M
