-- BibTeX/BibLaTeX Support
local M = {}

function M.setup()
    -- BibTeX compilation
    vim.api.nvim_create_user_command("BibtexCompile", function()
        local main_file = vim.fn.expand("%:r")
        vim.cmd("!bibtex " .. main_file)
    end, { desc = "Compile BibTeX" })
    
    -- Full build with bibliography
    vim.api.nvim_create_user_command("LatexFullBuild", function()
        local file = vim.fn.expand("%:r")
        vim.cmd("!pdflatex " .. file)
        vim.cmd("!bibtex " .. file)
        vim.cmd("!pdflatex " .. file)
        vim.cmd("!pdflatex " .. file)
    end, { desc = "Full LaTeX build with bibliography" })
end

M.setup()
return M
