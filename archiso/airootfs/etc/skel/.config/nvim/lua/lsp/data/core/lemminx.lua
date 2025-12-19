-- XML Language Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    local util = require("lspconfig.util")

    lspconfig.lemminx.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        -- Explicitly set root directory to prevent null URI errors
        root_dir = function(fname)
            return util.root_pattern(
                ".git",
                "pom.xml",
                "build.gradle",
                "build.gradle.kts"
            )(fname) or util.path.dirname(fname)
        end,
    })
end

M.setup()
return M
