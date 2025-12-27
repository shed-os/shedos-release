-- ═══════════════════════════════════════════════════════════
--                      COLOR TOOLS
-- ═══════════════════════════════════════════════════════════
--
-- Comprehensive color management for web development
--
-- Features:
--   - Inline color preview (see colors in your code)
--   - Color picker (choose colors visually)
--   - Multiple format support (hex, rgb, hsl, tailwind)
--   - Color conversion between formats
--   - Tailwind CSS integration
--
-- Perfect for:
--   - Frontend web development
--   - CSS/SCSS/Tailwind work
--   - Design system development
--   - UI debugging
--
-- ═══════════════════════════════════════════════════════════

return {
  -- nvim-colorizer - Inline color preview
  {
    "NvChad/nvim-colorizer.lua",
    event = "BufReadPre",
    config = function()
      require("colorizer").setup({
        -- Filetypes to enable colorizer
        filetypes = {
          "*", -- Enable for all files by default
          -- Special configurations for specific filetypes
          css = { rgb_fn = true, hsl_fn = true },
          scss = { rgb_fn = true, hsl_fn = true },
          html = { names = true },
          javascript = { RGB = true, RRGGBB = true, RRGGBBAA = true },
          typescript = { RGB = true, RRGGBB = true, RRGGBBAA = true },
          typescriptreact = { RGB = true, RRGGBB = true, tailwind = true },
          javascriptreact = { RGB = true, RRGGBB = true, tailwind = true },
          vue = { RGB = true, RRGGBB = true, tailwind = true },
          svelte = { RGB = true, RRGGBB = true, tailwind = true },
        },
        -- User default options
        user_default_options = {
          RGB = true, -- #RGB hex codes
          RRGGBB = true, -- #RRGGBB hex codes
          names = true, -- "Name" codes like Blue or blue
          RRGGBBAA = true, -- #RRGGBBAA hex codes
          AARRGGBB = true, -- 0xAARRGGBB hex codes
          rgb_fn = true, -- CSS rgb() and rgba() functions
          hsl_fn = true, -- CSS hsl() and hsla() functions
          css = true, -- Enable all CSS features: rgb_fn, hsl_fn, names, RGB, RRGGBB
          css_fn = true, -- Enable all CSS *functions*: rgb_fn, hsl_fn
          -- Available modes for `mode`: foreground, background,  virtualtext
          mode = "background", -- Set the display mode (background is most visible)
          -- Available methods: false / "normal" / "lsp" / "both"
          -- "normal" updates on BufEnter, "lsp" updates on changes
          tailwind = "both", -- Enable tailwind colors (requires LSP)
          sass = { enable = true, parsers = { "css" } }, -- Enable sass colors
          virtualtext = "■", -- Character to use for virtualtext mode
          -- Update color values even if buffer is not focused
          always_update = false,
        },
        -- All the sub-options of filetypes apply to buftypes
        buftypes = {},
      })

      -- Keybindings
      vim.keymap.set("n", "<leader>ct", "<cmd>ColorizerToggle<cr>", { desc = "Color: Toggle Colorizer" })
      vim.keymap.set("n", "<leader>cr", "<cmd>ColorizerReloadAllBuffers<cr>", { desc = "Color: Reload All Buffers" })
    end,
  },

  -- ccc.nvim - Advanced color picker
  {
    "uga-rosa/ccc.nvim",
    cmd = { "CccPick", "CccConvert", "CccHighlighterEnable", "CccHighlighterDisable", "CccHighlighterToggle" },
    keys = {
      { "<leader>cp", "<cmd>CccPick<cr>", desc = "Color: Pick Color" },
      { "<leader>cc", "<cmd>CccConvert<cr>", desc = "Color: Convert Format" },
      { "<leader>ch", "<cmd>CccHighlighterToggle<cr>", desc = "Color: Toggle Highlighter" },
    },
    config = function()
      local ccc = require("ccc")
      local mapping = ccc.mapping

      ccc.setup({
        -- Highlighter options
        highlighter = {
          auto_enable = false, -- Don't auto-enable (use manual toggle)
          max_byte = 100 * 1024, -- 100KB (don't highlight huge files)
          lsp = true, -- Use LSP for enhanced highlighting
          excludes = { "lazy", "mason", "help", "neo-tree" }, -- Exclude special buffers
        },

        -- Picker options
        pickers = {
          ccc.picker.hex,
          ccc.picker.css_rgb,
          ccc.picker.css_hsl,
        },

        -- Color conversion
        convert = {
          { ccc.picker.hex, ccc.output.css_rgb },
          { ccc.picker.css_rgb, ccc.output.css_hsl },
          { ccc.picker.css_hsl, ccc.output.hex },
        },

        -- Recognize color formats
        recognize = {
          input = true, -- Enable input of colors
          output = true, -- Enable output of colors
        },

        -- Keymappings within the picker
        mappings = {
          ["<CR>"] = mapping.complete,
          ["q"] = mapping.quit,
          ["<Esc>"] = mapping.quit,
          ["L"] = mapping.increase10,
          ["H"] = mapping.decrease10,
          ["l"] = mapping.increase1,
          ["h"] = mapping.decrease1,
          ["i"] = mapping.set_min,
          ["a"] = mapping.set_max,
          ["0"] = mapping.set0,
          ["1"] = mapping.set50,
          ["2"] = mapping.set100,
          ["o"] = mapping.cycle_output_mode,
          ["<Tab>"] = mapping.goto_next,
          ["<S-Tab>"] = mapping.goto_prev,
        },

        -- Save/load palette
        preserve = false,
      })

      -- Auto-commands for specific filetypes
      local augroup = vim.api.nvim_create_augroup("CccConfig", { clear = true })

      -- Auto-enable highlighter for CSS/SCSS files
      vim.api.nvim_create_autocmd("FileType", {
        group = augroup,
        pattern = { "css", "scss", "sass", "less", "stylus" },
        callback = function()
          vim.cmd("CccHighlighterEnable")
        end,
      })

      -- Auto-enable for HTML/JSX/TSX (but only for inline styles)
      vim.api.nvim_create_autocmd("FileType", {
        group = augroup,
        pattern = { "html", "javascriptreact", "typescriptreact", "vue", "svelte" },
        callback = function()
          -- Only enable if file contains style tags or inline styles
          local lines = vim.api.nvim_buf_get_lines(0, 0, 100, false)
          for _, line in ipairs(lines) do
            if line:match("style=") or line:match("<style") then
              vim.cmd("CccHighlighterEnable")
              break
            end
          end
        end,
      })
    end,
  },

  -- Tailwind CSS color support
  {
    "themaxmarchuk/tailwindcss-colors.nvim",
    ft = { "html", "javascriptreact", "typescriptreact", "vue", "svelte" },
    config = function()
      require("tailwindcss-colors").setup()
    end,
  },

  -- Which-key integration
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>c", group = "code/color", icon = " " },
        { "<leader>cp", desc = "Color: Pick" },
        { "<leader>cc", desc = "Color: Convert" },
        { "<leader>ch", desc = "Color: Toggle Highlighter" },
        { "<leader>ct", desc = "Color: Toggle Colorizer" },
        { "<leader>cr", desc = "Color: Reload Buffers" },
      },
    },
  },
}
