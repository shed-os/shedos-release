-- ═══════════════════════════════════════════════════════════
--                  OPENAPI LSP ENTRY POINT
-- ═══════════════════════════════════════════════════════════
--
-- Full OpenAPI/Swagger support with:
-- - LSP integration (yamlls + spectral)
-- - Live preview (Swagger UI / ReDoc)
-- - Code generation (client SDKs + server stubs)
-- - Mock API server (Prism)
-- - Advanced validation (Spectral)
--
-- Enable/disable by uncommenting/commenting the require
-- statement in lua/lsp/init.lua
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Use shared helpers for consistency
local helpers = require("lsp.helpers")

-- Setup function called when OpenAPI file is detected
function M.setup()
  -- Load core LSP configuration
  helpers.safe_setup("lsp.openapi.core.openapi-ls")

  -- Load OpenAPI features
  helpers.safe_setup("lsp.openapi.features.preview")
  helpers.safe_setup("lsp.openapi.features.codegen")
  helpers.safe_setup("lsp.openapi.features.validator")
  helpers.safe_setup("lsp.openapi.features.mock-server")

  -- Detection utility is loaded on-demand (no setup needed)
  -- helpers.safe_require("lsp.openapi.utils.detection")

  vim.notify("OpenAPI LSP features loaded", vim.log.levels.INFO)
end

-- Auto-detect and setup OpenAPI files
local detection = require("lsp.openapi.utils.detection")

detection.setup_detection_autocmd(function(bufnr, version)
  -- OpenAPI file detected, run setup (once)
  M.setup()

  -- Set buffer variable to mark as OpenAPI
  vim.api.nvim_buf_set_var(bufnr, "is_openapi", true)
  vim.api.nvim_buf_set_var(bufnr, "openapi_version", version)

  -- Show detection notification
  vim.notify(
    string.format("OpenAPI %s detected in %s", version, vim.fn.fnamemodify(vim.api.nvim_buf_get_name(bufnr), ":t")),
    vim.log.levels.INFO
  )
end)

return M
