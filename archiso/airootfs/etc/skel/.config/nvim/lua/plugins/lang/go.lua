-- ═══════════════════════════════════════════════════════════
--                      GO LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════

return {
  -- Add to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "go", "gomod", "gowork", "gosum" })
    end,
  },

  -- Add tools to Mason
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "gopls", -- Go LSP
        "gofumpt", -- Formatter
        "goimports", -- Import formatter
        "golangci-lint", -- Linter
        "delve", -- Debugger
      })
    end,
  },

  -- nvim-dap (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    config = function()
      -- DAP configuration is handled by lua/lsp/go/core/dap.lua
    end,
  },

  -- nvim-dap-ui
  {
    "rcarriga/nvim-dap-ui",
    lazy = true,
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      -- DAP UI configuration is handled by lua/lsp/go/ui/dap-ui.lua
    end,
  },

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.go = { "goimports", "gofumpt" }
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.go = { "golangcilint" }

      -- Configure golangci-lint to use custom config
      local golangcilint = require("lint").linters.golangcilint
      golangcilint.args = {
        "run",
        "--out-format",
        "json",
        "--config",
        vim.fn.stdpath("config") .. "/.golangci.yml",
      }
    end,
  },

  -- Testing with Neotest
  {
    "nvim-neotest/neotest",
    dependencies = { "nvim-neotest/neotest-go" },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(opts.adapters, require("neotest-go"))
    end,
  },
}
