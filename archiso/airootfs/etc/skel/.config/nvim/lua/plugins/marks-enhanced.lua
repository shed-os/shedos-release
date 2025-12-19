-- ═══════════════════════════════════════════════════════════
--                  ENHANCED BOOKMARK SYSTEM
-- ═══════════════════════════════════════════════════════════
--
-- Unlimited bookmarks with visual indicators
-- Complements Harpoon (which is limited to 4 files)
--
-- Usage:
--   mx - Set mark 'x'
--   'x - Jump to mark 'x'
--   m, - Set next available mark
--   m; - Preview mark
--   dmx - Delete mark 'x'
--
-- ═══════════════════════════════════════════════════════════

return {
  "chentoast/marks.nvim",
  event = "VeryLazy",
  opts = {
    -- Default marks to show
    default_mappings = true,

    -- Builtin marks to show (. = last change, < = last visual selection start, etc.)
    builtin_marks = { ".", "<", ">", "^" },

    -- Whether movements cycle back to the beginning/end of buffer
    cyclic = true,

    -- Force write shada on every mark modification
    force_write_shada = false,

    -- How often (in ms) to redraw signs/recompute mark positions
    refresh_interval = 250,

    -- Sign priorities for each type of mark
    sign_priority = { lower = 10, upper = 15, builtin = 8, bookmark = 20 },

    -- Which groups to display marks from
    excluded_filetypes = {
      "qf",
      "NvimTree",
      "toggleterm",
      "TelescopePrompt",
      "alpha",
      "netrw",
      "aerial",
    },

    -- Mappings for navigating marks
    mappings = {
      set_next = "m,", -- Set next available lowercase mark
      next = "m]", -- Jump to next mark in buffer
      prev = "m[", -- Jump to previous mark in buffer
      preview = "m;", -- Preview mark (transient)
      delete = "dm", -- Delete mark at cursor
      delete_line = "dm-", -- Delete all marks on current line
      delete_buf = "dm<space>", -- Delete all marks in buffer
    },
  },
  config = function(_, opts)
    require("marks").setup(opts)

    -- Custom keybindings for mark navigation
    vim.keymap.set("n", "<leader>m", "<cmd>MarksListBuf<cr>", { desc = "Marks: List Buffer Marks" })
    vim.keymap.set("n", "<leader>M", "<cmd>MarksListAll<cr>", { desc = "Marks: List All Marks" })
  end,
}
