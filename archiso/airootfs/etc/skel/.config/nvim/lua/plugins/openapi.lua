-- ═══════════════════════════════════════════════════════════
--                   OPENAPI/SWAGGER SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- Full OpenAPI/Swagger editor with:
-- - Syntax highlighting & LSP support
-- - Live preview (browser + floating window)
-- - Code generation (multiple languages)
-- - Mock API server
-- - Validation & linting
-- - Schema navigation
--
-- ═══════════════════════════════════════════════════════════

return {
  -- Add OpenAPI parsers to Treesitter
  {
    "nvim-treesitter/nvim-treesitter",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "yaml",
        "json",
      })
    end,
  },

  -- Add OpenAPI tools to Mason
  {
    "mason-org/mason.nvim",
    optional = true,
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        -- LSP & Validation
        "yaml-language-server", -- YAML LSP with OpenAPI schema support
        "spectral-language-server", -- OpenAPI linting & validation

        -- Code Generation
        -- Note: openapi-generator requires manual installation via npm/brew
        -- We'll check for it at runtime and provide install instructions

        -- Formatting
        "prettier", -- YAML/JSON formatting
      })
    end,
  },

  -- Configure formatters for OpenAPI files
  {
    "stevearc/conform.nvim",
    optional = true,
    opts = function(_, opts)
      opts.formatters_by_ft = opts.formatters_by_ft or {}
      -- OpenAPI files are YAML/JSON, so use existing formatters
      -- Specific OpenAPI handling is in ftplugin
    end,
  },

  -- Swagger UI for preview (browser-based)
  -- This is a custom integration - we'll launch it via Node.js/Python servers
  -- No plugin needed, just runtime tooling

  -- Floating preview support
  {
    "iamcco/markdown-preview.nvim",
    optional = true,
    -- We'll use similar patterns for OpenAPI preview in floating windows
  },

  -- HTTP client for testing API endpoints from OpenAPI spec
  {
    "rest-nvim/rest.nvim",
    optional = true,
    -- Integration with OpenAPI specs to generate HTTP requests
  },
}
