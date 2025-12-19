-- ═══════════════════════════════════════════════════════════
--                 EDGY - SMART WINDOW MANAGEMENT
-- ═══════════════════════════════════════════════════════════
--
-- Intelligent edge window positioning and management
--
-- Features:
--   - Auto-position sidebars (snacks explorer, aerial, etc.)
--   - Smart bottom windows (terminal, diagnostics, quickfix)
--   - Persistent window layouts
--   - Pinning and unpinning windows
--   - Automatic size management
--
-- ═══════════════════════════════════════════════════════════

return {
  "folke/edgy.nvim",
  event = "VeryLazy",
  keys = {
    {
      "<leader>ue",
      function()
        require("edgy").toggle()
      end,
      desc = "Toggle Edgy",
    },
    {
      "<leader>uE",
      function()
        require("edgy").select()
      end,
      desc = "Edgy Select Window",
    },
  },
  opts = function()
    local opts = {
      -- Window positioning configuration
      bottom = {
        -- Bottom edge windows
        {
          ft = "toggleterm",
          size = { height = 0.4 },
          filter = function(buf, win)
            return vim.api.nvim_win_get_config(win).relative == ""
          end,
        },
        {
          ft = "lazyterm",
          title = "LazyTerm",
          size = { height = 0.4 },
          filter = function(buf)
            return not vim.b[buf].lazyterm_cmd
          end,
        },
        "Trouble",
        { ft = "qf", title = "QuickFix" },
        {
          ft = "help",
          size = { height = 20 },
          -- only show help buffers
          filter = function(buf)
            return vim.bo[buf].buftype == "help"
          end,
        },
        { title = "Spectre", ft = "spectre_panel", size = { height = 0.4 } },
        { title = "Neotest Output", ft = "neotest-output-panel", size = { height = 15 } },
      },
      left = {
        -- Left edge windows
        -- Snacks Explorer
        {
          title = "Explorer",
          ft = "snacks_explorer",
          pinned = false,
          size = { width = 0.25 },
        },
        -- Outline
        {
          ft = "Outline",
          pinned = false,
          open = "SymbolsOutlineOpen",
        },
      },
      right = {
        -- Right edge windows
        {
          title = "Aerial",
          ft = "aerial",
          pinned = false,
          open = "AerialOpen",
          size = { width = 0.2 },
        },
        {
          title = "Grug Far",
          ft = "grug-far",
          size = { width = 0.4 },
        },
      },
      keys = {
        -- Increase width
        ["<c-Right>"] = function(win)
          win:resize("width", 2)
        end,
        -- Decrease width
        ["<c-Left>"] = function(win)
          win:resize("width", -2)
        end,
        -- Increase height
        ["<c-Up>"] = function(win)
          win:resize("height", 2)
        end,
        -- Decrease height
        ["<c-Down>"] = function(win)
          win:resize("height", -2)
        end,
      },
    }
    return opts
  end,
}
