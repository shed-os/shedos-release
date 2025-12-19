-- LaTeX filetype settings
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.expandtab = true
vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.spell = true
vim.opt_local.spelllang = "en_us"

local opts = { buffer = true, silent = true }
vim.keymap.set("n", "<leader>lb", "<cmd>TexlabBuild<CR>", 
    vim.tbl_extend("force", opts, { desc = "Build LaTeX" }))
vim.keymap.set("n", "<leader>lv", "<cmd>LatexView<CR>", 
    vim.tbl_extend("force", opts, { desc = "View PDF" }))
