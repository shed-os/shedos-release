-- Markdown filetype settings (override existing)
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.expandtab = true
vim.opt_local.wrap = true
vim.opt_local.linebreak = true
vim.opt_local.spell = true
vim.opt_local.conceallevel = 2

local opts = { buffer = true, silent = true }
vim.keymap.set("n", "<leader>mp", "<cmd>MarkdownPreview<CR>", 
    vim.tbl_extend("force", opts, { desc = "Preview" }))
