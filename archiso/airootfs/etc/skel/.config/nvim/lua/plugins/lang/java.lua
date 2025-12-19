-- Java language plugin configuration
-- Compatible with LazyVim 14.x+ and Neovim 0.11.2+
return {

  -- Add Java to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, { "java" })
    end,
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, {
        "jdtls", -- Java LSP
        "java-debug-adapter", -- DAP for Java
        "java-test", -- Java test runner
        "google-java-format", -- Formatter
        "checkstyle", -- Linter
      })
    end,
  },
  -- nvim-dap (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    config = function()
      -- DAP configuration is handled by lua/lsp/java/core/dap.lua
      -- This just loads the plugin without running any setup
    end,
  },

  -- nvim-dap-ui
  {
    "rcarriga/nvim-dap-ui",
    lazy = true,
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      -- DAP UI configuration is handled by lua/lsp/java/ui/dap-ui.lua
    end,
  },

  -- Java LSP with advanced features
  {
    "mfussenegger/nvim-jdtls",
    ft = { "java" },
    dependencies = {
      "mfussenegger/nvim-dap",
      "rcarriga/nvim-dap-ui",
      "nvim-telescope/telescope.nvim", -- Optional
    },
    config = function()
      -- Configuration is handled by after/ftplugin/java.lua
      -- This just ensures the plugin is loaded
    end,
  },

  {
    "JavaHello/spring-boot.nvim",
    ft = "java",
    dependencies = {
      "mfussenegger/nvim-jdtls",
      -- Compatible with both fzf-lua (LazyVim 14.x+) and telescope
      { "ibhagwan/fzf-lua", optional = true },
      { "nvim-telescope/telescope.nvim", optional = true },
    },
  },

  {
    "nvim-neotest/neotest",
    optional = true,
    dependencies = { "rcasia/neotest-java" },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(opts.adapters, require("neotest-java"))
    end,
  },

  -- Configure formatters
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      opts.formatters_by_ft.java = { "google-java-format" }
    end,
  },

  -- Configure linters
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = function(_, opts)
      opts.linters_by_ft = opts.linters_by_ft or {}
      opts.linters_by_ft.java = { "checkstyle" }

      -- Configure checkstyle to use custom config
      local checkstyle = require("lint").linters.checkstyle
      checkstyle.args = {
        "-c",
        vim.fn.stdpath("config") .. "/checkstyle.xml",
      }
    end,
  },
}
