-- ═══════════════════════════════════════════════════════════
--               STARTUP TIME MONITORING
-- ═══════════════════════════════════════════════════════════
--
-- Monitor Neovim startup performance
-- Track which plugins slow down your startup
-- Essential with 90+ plugins!
--
-- ═══════════════════════════════════════════════════════════

return {
  "dstein64/vim-startuptime",
  cmd = "StartupTime",
  keys = {
    { "<leader>st", "<cmd>StartupTime<cr>", desc = "Startup Time" },
  },
  config = function()
    vim.g.startuptime_tries = 10 -- Average over 10 runs for accuracy
    vim.g.startuptime_exe_path = vim.v.progpath -- Use current nvim executable
  end,
}
