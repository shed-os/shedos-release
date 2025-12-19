-- ═══════════════════════════════════════════════════════════
--            DISABLE AUTOFORMAT FOR SQL FILES
-- ═══════════════════════════════════════════════════════════
--
-- SQL files are causing issues with formatters removing spaces
-- between keywords (e.g., "CREATE SCHEMA" → "CREATESCHEMA")
--
-- This file completely disables autoformatting for SQL files.
--
-- ═══════════════════════════════════════════════════════════

return {
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        sql = {}, -- No formatters for SQL files
      },
    },
  },

  -- Disable autoformat for SQL files on FileType event
  {
    "LazyVim/LazyVim",
    opts = function()
      -- Create autocmd to disable autoformat for SQL files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = "sql",
        callback = function()
          vim.b.autoformat = false
        end,
      })
    end,
  },
}
