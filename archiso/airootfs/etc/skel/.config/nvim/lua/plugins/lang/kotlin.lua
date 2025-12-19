-- ═══════════════════════════════════════════════════════════
--                    KOTLIN LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════

return {
  -- Add Kotlin to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "kotlin" })
    end,
  },

  -- Add Kotlin LSP to Mason
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "kotlin-language-server",
        "ktlint", -- Formatter and linter
      })
    end,
  },

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.kotlin = { "ktlint" }
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.kotlin = { "ktlint" }
    end,
  },
}
