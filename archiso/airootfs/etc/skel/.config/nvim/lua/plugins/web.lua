-- ═══════════════════════════════════════════════════════════
--                    WEB LANGUAGES SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- HTML, CSS, SCSS, TailwindCSS with full LSP support
--
-- ═══════════════════════════════════════════════════════════

return {
  -- Add to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "html",
        "css",
        "scss",
      })
    end,
  },

  -- Add tools to Mason
  -- Mason tools are managed centrally in lua/plugins/mason-tools.lua

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.html = { "prettier" }
      opts.formatters_by_ft.css = { "prettier" }
      opts.formatters_by_ft.scss = { "prettier" }
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.css = { "stylelint" }
      opts.linters_by_ft.scss = { "stylelint" }

      -- Configure stylelint to use custom config
      local stylelint = require("lint").linters.stylelint
      stylelint.args = {
        "--formatter=json",
        "--stdin-filename",
        function()
          return vim.api.nvim_buf_get_name(0)
        end,
        "--config",
        vim.fn.stdpath("config") .. "/.stylelintrc.json",
      }
    end,
  },

  -- TailwindCSS colorizer
  {
    "NvChad/nvim-colorizer.lua",
    optional = true,
    opts = {
      user_default_options = {
        tailwind = true,
      },
    },
  },

  {
    "windwp/nvim-ts-autotag",
    ft = { "html", "xml", "javascript", "typescript", "javascriptreact", "typescriptreact" },
    opts = {},
  },
}
