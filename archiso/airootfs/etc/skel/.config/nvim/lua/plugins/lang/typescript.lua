-- ═══════════════════════════════════════════════════════════
--                TYPESCRIPT/JAVASCRIPT SUPPORT
-- ═══════════════════════════════════════════════════════════

return {
  -- Add to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "javascript",
        "typescript",
        "tsx",
        "jsdoc",
      })
    end,
  },

  -- Add tools to Mason
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "typescript-language-server", -- TS/JS LSP
        "eslint-lsp", -- ESLint LSP for linting (replaces eslint_d)
        "prettier", -- Formatter
        "prettierd", -- Faster prettier
        "js-debug-adapter", -- Debug adapter
      })
    end,
  },

  -- nvim-dap (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    config = function()
      -- DAP configuration is handled by lua/lsp/typescript/core/dap.lua
    end,
  },

  -- nvim-dap-ui
  {
    "rcarriga/nvim-dap-ui",
    lazy = true,
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      -- DAP UI configuration is handled by lua/lsp/typescript/ui/dap-ui.lua
    end,
  },

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.javascript = { "prettier" }
      opts.formatters_by_ft.javascriptreact = { "prettier" }
      opts.formatters_by_ft.typescript = { "prettier" }
      opts.formatters_by_ft.typescriptreact = { "prettier" }
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      -- Disable eslint_d - we use eslint-lsp instead which has better integration
      -- JavaScript/TypeScript linting is provided by:
      --   - eslint-lsp (for projects with .eslintrc.*)
      --   - tsserver (for TypeScript type checking)
      -- This avoids the "could not parse linter output" errors from eslint_d
    end,
  },

  -- Testing with Neotest (Jest/Vitest)
  {
    "nvim-neotest/neotest",
    dependencies = { "nvim-neotest/neotest-jest" },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(
        opts.adapters,
        require("neotest-jest")({
          jestCommand = "npm test --",
          jestConfigFile = "jest.config.js",
          env = { CI = true },
          cwd = function()
            return vim.fn.getcwd()
          end,
        })
      )
    end,
  },

  -- Note: typescript-tools.nvim is disabled to avoid conflict with tsserver
  -- We use the standard tsserver configuration in lua/lsp/typescript/core/tsserver.lua
  -- {
  --   "pmizio/typescript-tools.nvim",
  --   ft = { "typescript", "typescriptreact" },
  --   dependencies = { "nvim-lua/plenary.nvim" },
  --   opts = {},
  -- },
}
