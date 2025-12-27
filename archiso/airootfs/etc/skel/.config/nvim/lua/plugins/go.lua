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
  
  -- Inject Legacy Go Keymaps
  {
    "neovim/nvim-lspconfig",
    opts = function()
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          if client and client.name == "gopls" then
             local opts = { buffer = args.buf, silent = true }
             vim.keymap.set("n", "<leader>gb", "<cmd>GoBuild<CR>", vim.tbl_extend("force", opts, { desc = "Go: Build" }))
             vim.keymap.set("n", "<leader>gr", "<cmd>GoRun<CR>", vim.tbl_extend("force", opts, { desc = "Go: Run" }))
             vim.keymap.set("n", "<leader>gt", "<cmd>GoTest<CR>", vim.tbl_extend("force", opts, { desc = "Go: Test" }))
             vim.keymap.set("n", "<leader>gf", "<cmd>GoFmt<CR>", vim.tbl_extend("force", opts, { desc = "Go: Format" }))
             vim.keymap.set("n", "<leader>gi", "<cmd>GoImports<CR>", vim.tbl_extend("force", opts, { desc = "Go: Organize Imports" }))
          end
        end,
      })
    end,
  },
}
