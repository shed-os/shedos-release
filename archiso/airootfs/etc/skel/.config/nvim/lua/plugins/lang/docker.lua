-- ═══════════════════════════════════════════════════════════
--                   DOCKER LANGUAGE SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- Complete Docker and Docker Compose support for DevOps work
--
-- Features:
--   - Dockerfile LSP (dockerfile-language-server)
--   - Docker Compose LSP (docker-compose-language-service)
--   - Hadolint (Dockerfile linter)
--   - Syntax highlighting
--   - Auto-completion
--   - Diagnostics and linting
--
-- ═══════════════════════════════════════════════════════════

return {
  -- LSP Configuration
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        -- Dockerfile LSP
        dockerls = {
          settings = {
            docker = {
              languageserver = {
                formatter = {
                  ignoreMultilineInstructions = true,
                },
              },
            },
          },
        },
        -- Docker Compose LSP
        docker_compose_language_service = {
          settings = {},
        },
      },
    },
  },

  -- Mason: Auto-install LSP servers and tools
  {
    "williamboman/mason.nvim",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "dockerfile-language-server", -- Dockerfile LSP
        "docker-compose-language-service", -- Docker Compose LSP
        "hadolint", -- Dockerfile linter
      })
    end,
  },

  -- Treesitter: Syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "dockerfile",
      })
    end,
  },

  -- Linting with hadolint
  {
    "mfussenegger/nvim-lint",
    optional = true,
    opts = {
      linters_by_ft = {
        dockerfile = { "hadolint" },
      },
    },
  },

  -- Docker Commands Integration
  -- Note: Keybindings now use <leader>cd prefix (defined in which-key-enhanced.lua)
  -- to avoid conflict with Database client (<leader>D)
}
