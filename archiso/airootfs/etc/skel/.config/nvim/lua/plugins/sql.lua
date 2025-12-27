-- ═══════════════════════════════════════════════════════════
--                      SQL LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════

return {
  -- Add to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "sql" })
    end,
  },

  -- Add tools to Mason
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "sqls", -- SQL LSP
        "sqlfluff", -- SQL linter/formatter
      })
    end,
  },
  
  -- SQL Query Runner (Migrated from manual config)
  {
    "tpope/vim-dadbod",
    dependencies = {
      "kristijanhusak/vim-dadbod-ui",
      "kristijanhusak/vim-dadbod-completion",
    },
    config = function()
      require("config.sql_query_runner").setup()
    end,
  },

  -- NOTE: Formatters and linters disabled for SQL
  -- sqlfluff was causing issues by removing spaces between keywords
  -- Example: "CREATE SCHEMA" became "CREATESCHEMA"
  -- If you want to re-enable, uncomment the sections below
}
