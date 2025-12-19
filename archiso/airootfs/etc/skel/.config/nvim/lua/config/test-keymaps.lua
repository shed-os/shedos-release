-- ═══════════════════════════════════════════════════════════
--              UNIFIED TEST RUNNER KEYMAPS
-- ═══════════════════════════════════════════════════════════
--
-- Consistent test running keymaps across all languages
-- Works with Neotest for supported languages
--
-- ═══════════════════════════════════════════════════════════

-- Test keymaps (using <leader>t prefix)
vim.keymap.set("n", "<leader>tn", function()
  require("neotest").run.run()
end, { desc = "Test: Run Nearest" })

vim.keymap.set("n", "<leader>tf", function()
  require("neotest").run.run(vim.fn.expand("%"))
end, { desc = "Test: Run File" })

vim.keymap.set("n", "<leader>ta", function()
  require("neotest").run.run(vim.fn.getcwd())
end, { desc = "Test: Run All" })

vim.keymap.set("n", "<leader>tl", function()
  require("neotest").run.run_last()
end, { desc = "Test: Run Last" })

vim.keymap.set("n", "<leader>ts", function()
  require("neotest").summary.toggle()
end, { desc = "Test: Toggle Summary" })

vim.keymap.set("n", "<leader>to", function()
  require("neotest").output.open({ enter = true })
end, { desc = "Test: Show Output" })

vim.keymap.set("n", "<leader>tO", function()
  require("neotest").output_panel.toggle()
end, { desc = "Test: Toggle Output Panel" })

vim.keymap.set("n", "<leader>td", function()
  require("neotest").run.run({ strategy = "dap" })
end, { desc = "Test: Debug Nearest" })

vim.keymap.set("n", "<leader>tS", function()
  require("neotest").run.stop()
end, { desc = "Test: Stop" })

vim.keymap.set("n", "<leader>tw", function()
  require("neotest").watch.toggle(vim.fn.expand("%"))
end, { desc = "Test: Watch File" })

-- Jump to next/previous test
vim.keymap.set("n", "]t", function()
  require("neotest").jump.next({ status = "failed" })
end, { desc = "Next Failed Test" })

vim.keymap.set("n", "[t", function()
  require("neotest").jump.prev({ status = "failed" })
end, { desc = "Previous Failed Test" })

-- Coverage keymaps
vim.keymap.set("n", "<leader>tc", function()
  require("coverage").load(true)
  require("coverage").show()
end, { desc = "Test: Show Coverage" })

vim.keymap.set("n", "<leader>tC", function()
  require("coverage").clear()
end, { desc = "Test: Clear Coverage" })

-- Which-key integration for test keymaps
local ok, wk = pcall(require, "which-key")
if ok then
  wk.add({
    { "<leader>t", group = "test" },
    { "<leader>tn", desc = "Test: Run Nearest" },
    { "<leader>tf", desc = "Test: Run File" },
    { "<leader>ta", desc = "Test: Run All" },
    { "<leader>tl", desc = "Test: Run Last" },
    { "<leader>ts", desc = "Test: Toggle Summary" },
    { "<leader>to", desc = "Test: Show Output" },
    { "<leader>tO", desc = "Test: Toggle Output Panel" },
    { "<leader>td", desc = "Test: Debug Nearest" },
    { "<leader>tS", desc = "Test: Stop" },
    { "<leader>tw", desc = "Test: Watch File" },
    { "<leader>tc", desc = "Test: Show Coverage" },
    { "<leader>tC", desc = "Test: Clear Coverage" },
    { "]t", desc = "Next Failed Test" },
    { "[t", desc = "Previous Failed Test" },
  })
end

return {}
