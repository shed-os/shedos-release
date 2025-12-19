-- Asciidoc Conversion Features
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("AsciidocToPDF", function()
        vim.cmd("!asciidoctor-pdf %")
    end, { desc = "Convert to PDF" })
    
    vim.api.nvim_create_user_command("AsciidocToDocbook", function()
        vim.cmd("!asciidoctor -b docbook %")
    end, { desc = "Convert to DocBook" })
end

M.setup()
return M
