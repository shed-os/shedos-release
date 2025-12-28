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
  -- Mason tools are managed centrally in lua/plugins/mason-tools.lua

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

  -- LSP Configuration (Migrated from manual config)
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- ESLint
        eslint = {
          settings = {
            workingDirectory = { mode = "auto" },
          },
          on_attach = function(client, bufnr)
            vim.api.nvim_create_autocmd("BufWritePre", {
              buffer = bufnr,
              command = "EslintFixAll",
            })
          end,
        },
        
        -- TypeScript (tsserver / ts_ls)
        ts_ls = {
          -- Disable the automatic Vue integration which crashes on startup if not installed
          init = function(client)
             -- Do nothing, preventing LazyVim's default which tries to load vue-language-server path
          end,
          keys = {
              { "<leader>th", function() vim.lsp.inlay_hint.enable(not vim.lsp.inlay_hint.is_enabled()) end, desc = "Toggle Inlay Hints" }
          },
          settings = {
            typescript = {
              inlayHints = {
                includeInlayParameterNameHints = "none",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = false,
                includeInlayVariableTypeHints = false,
                includeInlayVariableTypeHintsWhenTypeMatchesName = false,
                includeInlayPropertyDeclarationTypeHints = false,
                includeInlayFunctionLikeReturnTypeHints = false,
                includeInlayEnumMemberValueHints = false,
              },
            },
            javascript = {
              inlayHints = {
                includeInlayParameterNameHints = "none",
                includeInlayParameterNameHintsWhenArgumentMatchesName = false,
                includeInlayFunctionParameterTypeHints = false,
                includeInlayVariableTypeHints = false,
                includeInlayVariableTypeHintsWhenTypeMatchesName = false,
                includeInlayPropertyDeclarationTypeHints = false,
                includeInlayFunctionLikeReturnTypeHints = false,
                includeInlayEnumMemberValueHints = false,
              },
            },
          },
        },
      },
      setup = {
        ts_ls = function(_, opts)
          require("lazyvim.util").lsp.on_attach(function(client, bufnr)
            if client.name == "ts_ls" then
                -- Inlay hints disabled by user request
                if vim.lsp.inlay_hint then
                  vim.lsp.inlay_hint.enable(false, { bufnr = bufnr })
                end

            end
          end)
          return false -- make sure we don't override the default setup entirely, just attach our logic
        end,
      },
    },
  },
}
