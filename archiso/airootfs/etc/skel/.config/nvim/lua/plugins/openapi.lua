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
        "yaml-language-server",
        "spectral-language-server",
        "prettier",
      })

      -- Inject legacy OpenAPI/Data features via LspAttach
      vim.api.nvim_create_autocmd("LspAttach", {
        callback = function(args)
          local bufnr = args.buf
          local client = vim.lsp.get_client_by_id(args.data.client_id)
          
          if not client then return end
          
          -- 1. OpenAPI Features
          local ok_detect, detection = pcall(require, "config.features.openapi.utils.detection")
          if ok_detect then
             local is_openapi, version = detection.is_openapi_file(bufnr)
             if is_openapi then
               vim.b[bufnr].is_openapi = true
               local map_opts = { buffer = bufnr, silent = true }
               
               -- Preview
               vim.keymap.set("n", "<leader>op", "<cmd>OpenAPIPreview swagger<cr>", vim.tbl_extend("force", map_opts, { desc = "OpenAPI: Preview (Swagger UI)" }))
               vim.keymap.set("n", "<leader>or", "<cmd>OpenAPIPreview redoc<cr>", vim.tbl_extend("force", map_opts, { desc = "OpenAPI: Preview (ReDoc)" }))
               vim.keymap.set("n", "<leader>of", "<cmd>OpenAPIFloatingPreview<cr>", vim.tbl_extend("force", map_opts, { desc = "OpenAPI: Floating Preview" }))
               vim.keymap.set("n", "<leader>oP", "<cmd>OpenAPIStopPreview<cr>", vim.tbl_extend("force", map_opts, { desc = "OpenAPI: Stop Preview" }))
               
               -- Code Gen & Mock Server (Simplified for migration)
               vim.keymap.set("n", "<leader>og", "<cmd>OpenAPIGenerate<cr>", vim.tbl_extend("force", map_opts, { desc = "OpenAPI: Generate Code" }))
               vim.keymap.set("n", "<leader>om", "<cmd>OpenAPIMockToggle<cr>", vim.tbl_extend("force", map_opts, { desc = "OpenAPI: Toggle Mock Server" }))

               vim.notify("✓ OpenAPI " .. version .. " detected", vim.log.levels.INFO, { title = "OpenAPI" })
             end
          end

          -- 2. GitHub Actions
          local ok_gh, gh_actions = pcall(require, "config.features.data.features.github-actions")
          if ok_gh and gh_actions.is_github_actions_workflow(bufnr) then
             local map_opts = { buffer = bufnr, silent = true }
             vim.keymap.set("n", "<leader>ga", "<cmd>GHActionsValidate<cr>", vim.tbl_extend("force", map_opts, { desc = "GitHub Actions: Validate" }))
             vim.keymap.set("n", "<leader>gt", "<cmd>GHActionsTrigger<cr>", vim.tbl_extend("force", map_opts, { desc = "GitHub Actions: Trigger" }))
             vim.notify("✓ GitHub Actions workflow detected", vim.log.levels.INFO, { title = "GitHub Actions" })
          end

          -- 3. Azure Pipelines
          local ok_az, az_pipelines = pcall(require, "config.features.data.features.azure-pipelines")
          if ok_az and az_pipelines.is_azure_pipeline(bufnr) then
             local map_opts = { buffer = bufnr, silent = true }
             vim.keymap.set("n", "<leader>ap", "<cmd>AzurePipelinesValidate<cr>", vim.tbl_extend("force", map_opts, { desc = "Azure: Validate pipeline" }))
             vim.notify("✓ Azure Pipeline detected", vim.log.levels.INFO, { title = "Azure Pipelines" })
          end
        end,
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
