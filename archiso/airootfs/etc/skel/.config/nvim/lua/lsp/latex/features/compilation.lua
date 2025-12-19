-- LaTeX Compilation Features
local M = {}

function M.setup()
    -- Build commands
    vim.api.nvim_create_user_command("LatexBuild", function()
        vim.cmd("TexlabBuild")
    end, { desc = "Build LaTeX document" })
    
    vim.api.nvim_create_user_command("LatexClean", function()
        vim.cmd("TexlabClean")
    end, { desc = "Clean LaTeX auxiliary files" })
    
    -- Watch mode
    vim.api.nvim_create_user_command("LatexWatch", function()
        vim.fn.jobstart("latexmk -pdf -pvc -interaction=nonstopmode " .. vim.fn.expand("%"))
    end, { desc = "Watch and rebuild on save" })
    
    -- Quick compile with pdflatex
    vim.api.nvim_create_user_command("LatexCompile", function()
        vim.cmd("!pdflatex -interaction=nonstopmode %")
    end, { desc = "Quick compile with pdflatex" })
end

M.setup()
return M
