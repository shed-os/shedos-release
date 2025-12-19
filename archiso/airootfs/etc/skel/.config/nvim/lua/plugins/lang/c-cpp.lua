-- ═══════════════════════════════════════════════════════════
--                    C/C++ LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════

return {
  -- Add C/C++ to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "c", "cpp", "cmake" })
    end,
  },

  -- Add C/C++ tools to Mason
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "clangd", -- C/C++ LSP
        "clang-format", -- Formatter
        "cpptools", -- Debug adapter
        "cpplint", -- Linter
        "cmake-language-server", -- CMake LSP
      })
    end,
  },

  -- nvim-dap (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    config = function()
      -- DAP configuration is handled by lua/lsp/c-cpp/core/dap.lua
    end,
  },

  -- nvim-dap-ui
  {
    "rcarriga/nvim-dap-ui",
    lazy = true,
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      -- DAP UI configuration is handled by lua/lsp/c-cpp/ui/dap-ui.lua
    end,
  },

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.c = { "clang_format" }
      opts.formatters_by_ft.cpp = { "clang_format" }

      -- Note: Auto-format on save is DISABLED for C/C++ via lua/config/c-cpp-autocmds.lua
      -- It sets vim.b.autoformat = false to prevent reformatting incomplete code
      -- Format manually with <leader>cf when needed
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.c = { "cpplint" }
      opts.linters_by_ft.cpp = { "cpplint" }

      -- Configure cpplint to use custom config
      -- cpplint looks for CPPLINT.cfg in parent directories automatically
      -- We just need to ensure it runs from the config directory
      local cpplint = require("lint").linters.cpplint
      cpplint.args = {
        "--verbose=0",
        "--config=" .. vim.fn.stdpath("config") .. "/CPPLINT.cfg",
      }
    end,
  },

  -- Testing with Neotest (GoogleTest/Catch2)
  {
    "nvim-neotest/neotest",
    dependencies = { "alfaix/neotest-gtest" },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(opts.adapters, require("neotest-gtest"))
    end,
  },
}
