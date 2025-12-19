-- JSON Language Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    local util = require("lspconfig.util")

    lspconfig.jsonls.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        -- Explicitly set root directory to prevent null URI errors
        root_dir = function(fname)
            return util.root_pattern(
                ".git",
                "package.json",
                "tsconfig.json",
                "jsconfig.json"
            )(fname) or util.path.dirname(fname)
        end,
        settings = {
            json = {
                schemas = require("schemastore").json.schemas(),
                validate = { enable = true },
            },
        },
    })
end

M.setup()
return M
