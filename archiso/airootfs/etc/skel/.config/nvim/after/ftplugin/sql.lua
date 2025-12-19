-- SQL filetype settings
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.expandtab = true

-- ═══════════════════════════════════════════════════════════
-- SQL QUERY EXECUTION KEYMAPS
-- ═══════════════════════════════════════════════════════════

local opts = { buffer = 0, silent = true }

-- Execute queries
vim.keymap.set("n", "<leader>se", "<cmd>SQLExecute<cr>", vim.tbl_extend("force", opts, {
  desc = "SQL: Execute query under cursor",
}))
vim.keymap.set("v", "<leader>se", ":<C-u>SQLExecute<cr>", vim.tbl_extend("force", opts, {
  desc = "SQL: Execute selected query",
}))
vim.keymap.set("n", "<leader>sf", "<cmd>SQLExecuteFile<cr>", vim.tbl_extend("force", opts, {
  desc = "SQL: Execute entire file",
}))

-- Connection management
vim.keymap.set("n", "<leader>sc", "<cmd>SQLConnect<cr>", vim.tbl_extend("force", opts, {
  desc = "SQL: Connect to database",
}))
vim.keymap.set("n", "<leader>sr", "<cmd>SQLRecent<cr>", vim.tbl_extend("force", opts, {
  desc = "SQL: Recent queries",
}))

-- Database UI
vim.keymap.set("n", "<leader>sd", "<cmd>DBUIToggle<cr>", vim.tbl_extend("force", opts, {
  desc = "SQL: Toggle DBUI",
}))

-- Show which-key group label
local ok_wk, wk = pcall(require, "which-key")
if ok_wk and wk then
  wk.add({
    { "<leader>s", group = "SQL", buffer = 0 },
  })
end
