-- ═══════════════════════════════════════════════════════════
--                DATA FORMAT LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- JSON, YAML, TOML with schema validation
--
-- ═══════════════════════════════════════════════════════════

return {
  -- SchemaStore for JSON/YAML schemas
  {
    "b0o/schemastore.nvim",
    lazy = true,
    version = false, -- Last update is for blink.compat
  },

  -- Add languages to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "json",
        "json5",
        "jsonc",
        "yaml",
        "toml",
      })
    end,
  },

  -- Add LSP servers to Mason
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "json-lsp", -- JSON LSP
        "yaml-language-server", -- YAML LSP
        "taplo", -- TOML LSP
        "prettier", -- Formatter for JSON/YAML
        "yamllint", -- YAML linter
        "yamlfmt", -- YAML formatter
      })
    end,
  },

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.json = { "prettier" }
      opts.formatters_by_ft.jsonc = { "prettier" }
      opts.formatters_by_ft.json5 = { "prettier" }
      opts.formatters_by_ft.yaml = { "prettier" }
      opts.formatters_by_ft.toml = { "taplo" }
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.yaml = { "yamllint" }
    end,
  },
}
