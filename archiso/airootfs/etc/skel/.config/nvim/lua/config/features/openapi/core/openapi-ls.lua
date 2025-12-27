-- ═══════════════════════════════════════════════════════════
--                   OPENAPI LSP CONFIGURATION
-- ═══════════════════════════════════════════════════════════
--
-- Configures YAML Language Server with OpenAPI/Swagger schemas
-- and Spectral for advanced OpenAPI linting
--
-- ═══════════════════════════════════════════════════════════

local M = {}

---Setup OpenAPI LSP support
function M.setup()
  local ok, lspconfig = pcall(require, "lspconfig")
  if not ok then
    vim.notify("lspconfig not found. OpenAPI LSP disabled.", vim.log.levels.WARN)
    return
  end

  local ok_schemas, schemastore = pcall(require, "schemastore")
  if not ok_schemas then
    vim.notify("schemastore.nvim not found. OpenAPI schema validation disabled.", vim.log.levels.WARN)
    schemastore = nil
  end

  local detection = require("lsp.openapi.utils.detection")

  -- ═══════════════════════════════════════════════════════════
  -- YAML Language Server with OpenAPI Schemas
  -- ═══════════════════════════════════════════════════════════

  -- Enhanced YAML LS settings for OpenAPI
  local yaml_settings = {
    yaml = {
      schemaStore = {
        enable = true,
        url = "https://www.schemastore.org/api/json/catalog.json",
      },
      schemas = schemastore and schemastore.yaml.schemas() or {
        ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.0/schema.json"] = {
          "openapi.yaml",
          "openapi.yml",
          "**/openapi/*.yaml",
          "**/openapi/*.yml",
        },
        ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json"] = {
          "openapi.yaml",
          "openapi.yml",
          "**/openapi/*.yaml",
          "**/openapi/*.yml",
        },
        ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v2.0/schema.json"] = {
          "swagger.yaml",
          "swagger.yml",
          "**/swagger/*.yaml",
          "**/swagger/*.yml",
        },
      },
      format = {
        enable = true,
        singleQuote = false,
        bracketSpacing = true,
      },
      validate = true,
      hover = true,
      completion = true,
      customTags = {
        -- Support for common OpenAPI extensions
        "!Ref",
        "!Sub",
        "!GetAtt",
        "!Join",
      },
    },
  }

  -- Update existing yamlls configuration or create new one
  -- This extends the configuration from lua/lsp/data/core/yamlls.lua
  local yaml_config = {
    settings = yaml_settings,
    on_attach = function(client, bufnr)
      -- Check if this is an OpenAPI file
      local is_openapi, version = detection.is_openapi_file(bufnr)
      if is_openapi then
        vim.api.nvim_buf_set_var(bufnr, "openapi_version", version)
        vim.notify(
          string.format("OpenAPI %s detected - Enhanced LSP features enabled", version),
          vim.log.levels.INFO
        )
      end
    end,
  }

  -- Only setup if not already configured
  -- This allows the data module's yamlls to take precedence
  -- We'll enhance it in the on_attach callback instead

  -- ═══════════════════════════════════════════════════════════
  -- Spectral Language Server (Advanced OpenAPI Linting)
  -- ═══════════════════════════════════════════════════════════

  -- Check if spectral-language-server is available
  local spectral_available = vim.fn.executable("spectral-language-server") == 1

  if spectral_available then
    lspconfig.spectral.setup({
      filetypes = { "yaml", "json", "yml" },
      root_dir = function(fname)
        return lspconfig.util.root_pattern(".spectral.yaml", ".spectral.yml", ".spectral.json")(fname)
          or vim.fn.getcwd()
      end,
      settings = {
        enable = true,
        run = "onType",
        validateLanguages = { "yaml", "json", "yml" },
      },
      on_attach = function(client, bufnr)
        -- Only attach to OpenAPI files
        local is_openapi = detection.is_openapi_file(bufnr)
        if not is_openapi then
          vim.lsp.buf_detach_client(bufnr, client.id)
          return
        end

        vim.notify("Spectral linting enabled for OpenAPI spec", vim.log.levels.INFO)
      end,
    })
  else
    vim.notify(
      "spectral-language-server not found. Install with: npm install -g @stoplight/spectral-cli",
      vim.log.levels.WARN
    )
  end

  -- ═══════════════════════════════════════════════════════════
  -- LSP Keymaps for OpenAPI Files
  -- ═══════════════════════════════════════════════════════════

  vim.api.nvim_create_autocmd("LspAttach", {
    group = vim.api.nvim_create_augroup("OpenAPILspKeymaps", { clear = true }),
    callback = function(args)
      local bufnr = args.buf
      local is_openapi = detection.is_openapi_file(bufnr)

      if not is_openapi then
        return
      end

      -- Standard LSP keymaps for OpenAPI
      local opts = { buffer = bufnr, silent = true }

      vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to Definition" }))
      vim.keymap.set(
        "n",
        "gr",
        vim.lsp.buf.references,
        vim.tbl_extend("force", opts, { desc = "Find References" })
      )
      vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover Documentation" }))
      vim.keymap.set(
        "n",
        "<leader>ca",
        vim.lsp.buf.code_action,
        vim.tbl_extend("force", opts, { desc = "Code Actions" })
      )
      vim.keymap.set(
        "n",
        "<leader>rn",
        vim.lsp.buf.rename,
        vim.tbl_extend("force", opts, { desc = "Rename Symbol" })
      )
    end,
  })
end

return M
