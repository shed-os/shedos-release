-- Go filetype settings
vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.expandtab = false  -- Go uses tabs
vim.opt_local.colorcolumn = "120"

local opts = { buffer = true, silent = true }
vim.keymap.set("n", "<leader>gb", "<cmd>GoBuild<CR>", 
    vim.tbl_extend("force", opts, { desc = "Build" }))
vim.keymap.set("n", "<leader>gr", "<cmd>GoRun<CR>", 
    vim.tbl_extend("force", opts, { desc = "Run" }))
vim.keymap.set("n", "<leader>gt", "<cmd>GoTest<CR>", 
    vim.tbl_extend("force", opts, { desc = "Test" }))
vim.keymap.set("n", "<leader>gf", "<cmd>GoFmt<CR>", 
    vim.tbl_extend("force", opts, { desc = "Format" }))
vim.keymap.set("n", "<leader>gi", "<cmd>GoImports<CR>", 
    vim.tbl_extend("force", opts, { desc = "Organize imports" }))
