-- ═══════════════════════════════════════════════════════════
--                 KUBERNETES LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- Complete Kubernetes and Helm support for DevOps work
--
-- Features:
--   - YAML LSP with Kubernetes schemas
--   - Helm language server
--   - Kubernetes manifest validation
--   - Auto-completion for K8s resources
--   - Syntax highlighting
--
-- ═══════════════════════════════════════════════════════════

return {
  -- NOTE: yamlls configuration removed from here - it's now configured in:
  -- lua/lsp/data/core/yamlls.lua (with proper root_dir to prevent errors)
  -- This avoids duplicate LSP setup that was causing "Scheme is missing" errors

  -- LSP Configuration for Helm only
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Helm LSP
        helm_ls = {
          settings = {
            ["helm-ls"] = {
              yamlls = {
                enabled = true,
                diagnosticsLimit = 50,
                showDiagnosticsDirectly = false,
                path = "yaml-language-server",
                config = {
                  schemas = {
                    kubernetes = "templates/**",
                  },
                  completion = true,
                  hover = true,
                },
              },
            },
          },
        },
      },
    },
  },

  -- Mason: Auto-install LSP servers
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "yaml-language-server", -- YAML LSP
        "helm-ls", -- Helm language server
        "yamllint", -- YAML linter
        "yamlfmt", -- YAML formatter
      })
    end,
  },

  -- Treesitter: Syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "yaml",
      })
    end,
  },

  -- Formatting with yamlfmt
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = {
      formatters_by_ft = {
        yaml = { "yamlfmt" },
      },
    },
  },

  -- Linting with yamllint
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        yaml = { "yamllint" },
      },
    },
  },

  -- Kubernetes Commands Integration
  -- Note: Keybindings now use <leader>ck prefix (defined in which-key-enhanced.lua)
  -- to avoid conflict with other plugins
}
