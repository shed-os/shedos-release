-- ═══════════════════════════════════════════════════════════
--                    CODE SCREENSHOT TOOL
-- ═══════════════════════════════════════════════════════════
--
-- Create beautiful code screenshots for sharing
-- Perfect for documentation, presentations, and team collaboration
--
-- Features:
--   - Beautiful syntax-highlighted screenshots
--   - Automatic theme matching
--   - Line numbers and window decorations
--   - Visual selection support
--   - Multiple output formats
--
-- Requirements:
--   - silicon (install via: cargo install silicon)
--   OR
--   - code2img (alternative, no external dependencies)
--
-- ═══════════════════════════════════════════════════════════

return {
  -- NOTE: We're using silicon CLI directly via shell commands
  -- The nvim-silicon plugin was causing configuration issues
  -- Keybindings are defined in lua/config/screenshot-keymaps.lua

  -- Which-key integration
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>s", group = "search/screenshot", icon = " " },
        { "<leader>sc", desc = "Screenshot: Capture Selection", mode = "v" },
        { "<leader>sC", desc = "Screenshot: Capture File", mode = "n" },
        { "<leader>sb", desc = "Screenshot: Copy to Clipboard", mode = "v" },
      },
    },
  },

  -- Override LazyVim defaults that might conflict
  {
    "nvim-telescope/telescope.nvim",
    optional = true,
    keys = {
      -- Disable LazyVim's default <leader>sC if it exists
      { "<leader>sC", false },
    },
  },
}
