-- Markdown Preview Features
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("MarkdownPreview", function()
        vim.cmd("!glow %")
    end, { desc = "Preview markdown with glow" })
    
    vim.api.nvim_create_user_command("MarkdownToPDF", function()
        vim.cmd("!pandoc % -o %:r.pdf")
    end, { desc = "Convert to PDF with pandoc" })
    
    vim.api.nvim_create_user_command("MarkdownToHTML", function()
        vim.cmd("!pandoc % -o %:r.html")
    end, { desc = "Convert to HTML with pandoc" })
end

M.setup()
return M
