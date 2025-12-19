-- ═══════════════════════════════════════════════════════════
--            C/C++ AUTOCMDS - FIX FORMATTING ISSUES
-- ═══════════════════════════════════════════════════════════

local augroup = vim.api.nvim_create_augroup("CCppCustom", { clear = true })

-- Disable format-on-save for C/C++ to prevent reformatting incomplete code
vim.api.nvim_create_autocmd("FileType", {
  group = augroup,
  pattern = { "c", "cpp" },
  callback = function()
    -- Disable auto-format on save
    vim.b.autoformat = false

    -- Stay in insert mode after completion
    vim.api.nvim_buf_set_option(0, "formatoptions", "tcqj")

    -- Notify user that manual formatting is needed
    vim.notify(
      "C/C++: Auto-format disabled. Use <leader>cf to format manually",
      vim.log.levels.INFO,
      { timeout = 2000 }
    )
  end,
})

-- Prevent formatexpr from triggering on incomplete code
vim.api.nvim_create_autocmd("InsertEnter", {
  group = augroup,
  pattern = { "*.c", "*.cpp", "*.h", "*.hpp" },
  callback = function()
    -- Clear formatexpr in insert mode to prevent auto-formatting
    vim.bo.formatexpr = ""
  end,
})

-- Restore formatexpr when leaving insert mode (for manual formatting)
vim.api.nvim_create_autocmd("InsertLeave", {
  group = augroup,
  pattern = { "*.c", "*.cpp", "*.h", "*.hpp" },
  callback = function()
    -- Restore formatexpr for manual formatting via gq
    vim.bo.formatexpr = "v:lua.require'conform'.formatexpr()"
  end,
})
