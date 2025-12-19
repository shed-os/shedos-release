-- Zig filetype settings
vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.expandtab = true
vim.opt_local.colorcolumn = "100"

local opts = { buffer = true, silent = true }
vim.keymap.set("n", "<leader>zb", "<cmd>ZigBuild<CR>", 
    vim.tbl_extend("force", opts, { desc = "Build" }))
vim.keymap.set("n", "<leader>zr", "<cmd>ZigRun<CR>", 
    vim.tbl_extend("force", opts, { desc = "Run" }))
vim.keymap.set("n", "<leader>zt", "<cmd>ZigTest<CR>", 
    vim.tbl_extend("force", opts, { desc = "Test" }))
