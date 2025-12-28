-- ═══════════════════════════════════════════════════════════
--                    PYTHON LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════

return {
  -- Add to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "python" })
    end,
  },

  -- Add tools to Mason
  -- Mason tools are managed centrally in lua/plugins/mason-tools.lua

  -- nvim-dap (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    config = function()
      -- DAP configuration is handled by lua/lsp/python/core/dap.lua
    end,
  },

  -- nvim-dap-ui
  {
    "rcarriga/nvim-dap-ui",
    lazy = true,
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      -- DAP UI configuration is handled by lua/lsp/python/ui/dap-ui.lua
    end,
  },

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.python = { "isort", "black" }
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.python = { "flake8" }

      -- Configure flake8 to use custom config
      local flake8 = require("lint").linters.flake8
      flake8.args = {
        "--format=%(path)s:%(row)d:%(col)d:%(code)s:%(text)s",
        "--config=" .. vim.fn.stdpath("config") .. "/.flake8",
      }
    end,
  },

  -- Testing with Neotest
  {
    "nvim-neotest/neotest",
    dependencies = { "nvim-neotest/neotest-python" },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(
        opts.adapters,
        require("neotest-python")({
          dap = { justMyCode = false },
          runner = "pytest",
        })
      )
    end,
  },
}
