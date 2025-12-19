-- LaTeX Preview Features
local M = {}

function M.setup()
    -- Forward search (jump to PDF location)
    vim.api.nvim_create_user_command("LatexForward", function()
        vim.cmd("TexlabForward")
    end, { desc = "Forward search to PDF" })
    
    -- Open PDF viewer
    vim.api.nvim_create_user_command("LatexView", function()
        local pdf_file = vim.fn.expand("%:r") .. ".pdf"
        if vim.fn.filereadable(pdf_file) == 1 then
            vim.fn.jobstart("zathura " .. pdf_file .. " &", { detach = true })
        else
            vim.notify("PDF file not found. Build first.", vim.log.levels.WARN)
        end
    end, { desc = "Open PDF in viewer" })
end

M.setup()
return M
