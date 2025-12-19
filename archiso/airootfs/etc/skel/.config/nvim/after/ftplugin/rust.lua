-- Rust filetype settings
vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.expandtab = true
vim.opt_local.colorcolumn = "100"

local opts = { buffer = true, silent = true }
vim.keymap.set("n", "<leader>rb", "<cmd>RustBuild<CR>", 
    vim.tbl_extend("force", opts, { desc = "Build" }))
vim.keymap.set("n", "<leader>rr", "<cmd>RustRun<CR>", 
    vim.tbl_extend("force", opts, { desc = "Run" }))
vim.keymap.set("n", "<leader>rt", "<cmd>RustTest<CR>", 
    vim.tbl_extend("force", opts, { desc = "Test" }))
vim.keymap.set("n", "<leader>rc", "<cmd>RustCheck<CR>", 
    vim.tbl_extend("force", opts, { desc = "Check" }))
vim.keymap.set("n", "<leader>rf", "<cmd>RustFmt<CR>", 
    vim.tbl_extend("force", opts, { desc = "Format" }))
