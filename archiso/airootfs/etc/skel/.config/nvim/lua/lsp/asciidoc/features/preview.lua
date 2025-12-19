-- Asciidoc Preview
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("AsciidocPreview", function()
        local html_file = vim.fn.expand("%:r") .. ".html"
        vim.cmd("!asciidoctor % && xdg-open " .. html_file)
    end, { desc = "Preview Asciidoc" })
end

M.setup()
return M
