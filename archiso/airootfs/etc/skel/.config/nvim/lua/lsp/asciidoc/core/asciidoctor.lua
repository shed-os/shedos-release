-- Asciidoctor LSP Configuration
local M = {}

function M.setup()
    -- Note: No dedicated LSP server, using basic text support
    -- Can extend with custom implementation or use generic text server
    
    vim.api.nvim_create_user_command("AsciidocBuild", function()
        vim.cmd("!asciidoctor %")
    end, { desc = "Build Asciidoc to HTML" })
end

M.setup()
return M
