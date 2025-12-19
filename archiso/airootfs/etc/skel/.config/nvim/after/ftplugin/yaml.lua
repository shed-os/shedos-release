-- YAML filetype settings
vim.opt_local.shiftwidth = 2
vim.opt_local.tabstop = 2
vim.opt_local.expandtab = true

-- ═══════════════════════════════════════════════════════════
-- OPENAPI-SPECIFIC CONFIGURATION
-- ═══════════════════════════════════════════════════════════

-- Check if this is an OpenAPI file
local ok_detection, detection = pcall(require, "lsp.openapi.utils.detection")
if ok_detection then
  local is_openapi, version = detection.is_openapi_file(0)

  if is_openapi then
    -- Mark buffer as OpenAPI
    vim.b.is_openapi = true
    vim.b.openapi_version = version

    -- ═══════════════════════════════════════════════════════════
    -- OPENAPI KEYMAPS
    -- ═══════════════════════════════════════════════════════════

    local opts = { buffer = 0, silent = true }

    -- Preview
    vim.keymap.set("n", "<leader>op", "<cmd>OpenAPIPreview swagger<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Preview (Swagger UI)",
    }))
    vim.keymap.set("n", "<leader>or", "<cmd>OpenAPIPreview redoc<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Preview (ReDoc)",
    }))
    vim.keymap.set("n", "<leader>of", "<cmd>OpenAPIFloatingPreview<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Floating Preview",
    }))
    vim.keymap.set("n", "<leader>oP", "<cmd>OpenAPIStopPreview<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Stop Preview",
    }))

    -- Code Generation
    vim.keymap.set("n", "<leader>og", "<cmd>OpenAPIGenerate<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Generate Code (Interactive)",
    }))
    vim.keymap.set("n", "<leader>oc", function()
      vim.ui.input({ prompt = "Client language: " }, function(lang)
        if lang then
          vim.cmd("OpenAPIGenerateClient " .. lang)
        end
      end)
    end, vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Generate Client SDK",
    }))
    vim.keymap.set("n", "<leader>os", function()
      vim.ui.input({ prompt = "Server framework: " }, function(lang)
        if lang then
          vim.cmd("OpenAPIGenerateServer " .. lang)
        end
      end)
    end, vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Generate Server Stub",
    }))
    vim.keymap.set("n", "<leader>oh", "<cmd>OpenAPIGenerateHelp<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Code Generation Help",
    }))

    -- Validation
    vim.keymap.set("n", "<leader>ov", "<cmd>OpenAPIValidate<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Validate Spec",
    }))
    vim.keymap.set("n", "<leader>ol", "<cmd>OpenAPILint<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Lint Spec",
    }))
    vim.keymap.set("n", "<leader>oV", "<cmd>OpenAPIValidateStats<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Validation Stats",
    }))

    -- Mock Server
    vim.keymap.set("n", "<leader>om", "<cmd>OpenAPIMockToggle<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Toggle Mock Server",
    }))
    vim.keymap.set("n", "<leader>oM", "<cmd>OpenAPIMockStart<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Start Mock Server",
    }))
    vim.keymap.set("n", "<leader>ox", "<cmd>OpenAPIMockStop<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Stop Mock Server",
    }))
    vim.keymap.set("n", "<leader>oL", "<cmd>OpenAPIMockList<cr>", vim.tbl_extend("force", opts, {
      desc = "OpenAPI: List Mock Servers",
    }))
    vim.keymap.set("n", "<leader>ot", function()
      vim.ui.input({ prompt = "Endpoint (e.g., /api/users): " }, function(endpoint)
        if endpoint then
          vim.ui.input({ prompt = "Method (default GET): ", default = "GET" }, function(method)
            vim.cmd(string.format("OpenAPIMockTest %s %s", endpoint, method or "GET"))
          end)
        end
      end)
    end, vim.tbl_extend("force", opts, {
      desc = "OpenAPI: Test Endpoint",
    }))

    -- Show which-key group label
    local ok_wk, wk = pcall(require, "which-key")
    if ok_wk and wk then
      wk.add({
        { "<leader>o", group = "OpenAPI", buffer = 0 },
      })
    end

    -- Show OpenAPI detection message
    vim.notify(
      string.format("✓ OpenAPI %s detected - Enhanced features enabled", version),
      vim.log.levels.INFO,
      { title = "OpenAPI" }
    )
  end
end

-- ═══════════════════════════════════════════════════════════
-- GITHUB ACTIONS CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local ok_gh, gh_actions = pcall(require, "lsp.data.features.github-actions")
if ok_gh and gh_actions.is_github_actions_workflow(0) then
  local opts = { buffer = 0, silent = true }

  vim.keymap.set("n", "<leader>ga", "<cmd>GHActionsValidate<cr>", vim.tbl_extend("force", opts, {
    desc = "GitHub Actions: Validate workflow",
  }))
  vim.keymap.set("n", "<leader>gt", "<cmd>GHActionsTrigger<cr>", vim.tbl_extend("force", opts, {
    desc = "GitHub Actions: Trigger workflow",
  }))
  vim.keymap.set("n", "<leader>gr", "<cmd>GHActionsRuns<cr>", vim.tbl_extend("force", opts, {
    desc = "GitHub Actions: View runs",
  }))
  vim.keymap.set("n", "<leader>gl", "<cmd>GHActionsLogs<cr>", vim.tbl_extend("force", opts, {
    desc = "GitHub Actions: View logs",
  }))

  local ok_wk, wk = pcall(require, "which-key")
  if ok_wk and wk then
    wk.add({
      { "<leader>g", group = "GitHub Actions", buffer = 0 },
    })
  end

  vim.notify("✓ GitHub Actions workflow detected", vim.log.levels.INFO, { title = "GitHub Actions" })
end

-- ═══════════════════════════════════════════════════════════
-- AZURE PIPELINES CONFIGURATION
-- ═══════════════════════════════════════════════════════════

local ok_az, az_pipelines = pcall(require, "lsp.data.features.azure-pipelines")
if ok_az and az_pipelines.is_azure_pipeline(0) then
  local opts = { buffer = 0, silent = true }

  vim.keymap.set("n", "<leader>ap", "<cmd>AzurePipelinesValidate<cr>", vim.tbl_extend("force", opts, {
    desc = "Azure: Validate pipeline",
  }))
  vim.keymap.set("n", "<leader>ar", "<cmd>AzurePipelinesRun<cr>", vim.tbl_extend("force", opts, {
    desc = "Azure: Run pipeline",
  }))
  vim.keymap.set("n", "<leader>al", "<cmd>AzurePipelinesRuns<cr>", vim.tbl_extend("force", opts, {
    desc = "Azure: View pipeline runs",
  }))

  local ok_wk, wk = pcall(require, "which-key")
  if ok_wk and wk then
    wk.add({
      { "<leader>a", group = "Azure Pipelines", buffer = 0 },
    })
  end

  vim.notify("✓ Azure Pipeline detected", vim.log.levels.INFO, { title = "Azure Pipelines" })
end
