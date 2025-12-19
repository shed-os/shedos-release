-- ═══════════════════════════════════════════════════════════
--                 AZURE PIPELINES SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- LSP support and validation for Azure Pipelines
--
-- ═══════════════════════════════════════════════════════════

local M = {}

---Check if file is an Azure Pipeline
---@param bufnr number|nil Buffer number (default: current)
---@return boolean is_pipeline True if Azure Pipeline
function M.is_azure_pipeline(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Common Azure Pipeline filenames
  if filepath:match("azure%-pipelines%.ya?ml$") or filepath:match("%.azure%-pipelines%.ya?ml$") then
    return true
  end

  -- Check file content for pipeline indicators
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 20, false)
  for _, line in ipairs(lines) do
    if line:match("^trigger:%s*$") or line:match("^%s*trigger:%s*$") then
      return true
    end
    if line:match("^stages:%s*$") or line:match("^%s*stages:%s*$") then
      return true
    end
    if line:match("^pool:%s*$") or line:match("^%s*pool:%s*$") then
      return true
    end
  end

  return false
end

---Validate pipeline using Azure CLI
---@param filepath string|nil Path to pipeline file (nil = current buffer)
function M.validate_pipeline(filepath)
  filepath = filepath or vim.api.nvim_buf_get_name(0)

  if vim.fn.executable("az") ~= 1 then
    vim.notify(
      "Azure CLI not found. Install: https://docs.microsoft.com/en-us/cli/azure/install-azure-cli",
      vim.log.levels.WARN
    )
    -- Fallback to basic YAML validation
    M.validate_yaml_basic(filepath)
    return
  end

  vim.notify("Validating Azure Pipeline...", vim.log.levels.INFO)

  -- Basic validation (Azure CLI doesn't have a direct validation command for pipelines)
  -- We'll do basic YAML validation
  M.validate_yaml_basic(filepath)
end

---Basic YAML validation
---@param filepath string Path to file
function M.validate_yaml_basic(filepath)
  if vim.fn.executable("yamllint") == 1 then
    local output = vim.fn.systemlist(string.format("yamllint -f parsable '%s'", filepath))

    if vim.v.shell_error == 0 then
      vim.notify("✓ Pipeline YAML is valid", vim.log.levels.INFO)
    else
      vim.notify("✗ YAML validation failed. See messages.", vim.log.levels.WARN)
      for _, line in ipairs(output) do
        if line ~= "" then
          vim.notify(line, vim.log.levels.WARN)
        end
      end
    end
  else
    vim.notify("yamllint not found. Install: pip install yamllint", vim.log.levels.WARN)
  end
end

---Run pipeline using Azure CLI
---@param pipeline_name string|nil Pipeline name (nil = prompt)
function M.run_pipeline(pipeline_name)
  if vim.fn.executable("az") ~= 1 then
    vim.notify("Azure CLI not found. Install from https://aka.ms/InstallAzureCLIDeb", vim.log.levels.ERROR)
    return
  end

  if not pipeline_name then
    vim.ui.input({
      prompt = "Pipeline name: ",
    }, function(input)
      if input and input ~= "" then
        M.run_pipeline(input)
      end
    end)
    return
  end

  -- Get organization and project
  vim.ui.input({
    prompt = "Organization: ",
  }, function(org)
    if not org or org == "" then
      return
    end

    vim.ui.input({
      prompt = "Project: ",
    }, function(project)
      if not project or project == "" then
        return
      end

      local cmd = string.format("az pipelines run --name '%s' --organization %s --project %s", pipeline_name, org, project)

      vim.fn.jobstart(cmd, {
        on_exit = function(_, exit_code)
          if exit_code == 0 then
            vim.notify("✓ Pipeline queued successfully", vim.log.levels.INFO)
          else
            vim.notify("✗ Failed to queue pipeline", vim.log.levels.ERROR)
          end
        end,
      })
    end)
  end)
end

---View pipeline runs
function M.view_pipeline_runs()
  if vim.fn.executable("az") ~= 1 then
    vim.notify("Azure CLI not found", vim.log.levels.ERROR)
    return
  end

  vim.ui.input({
    prompt = "Organization: ",
  }, function(org)
    if not org or org == "" then
      return
    end

    vim.ui.input({
      prompt = "Project: ",
    }, function(project)
      if not project or project == "" then
        return
      end

      vim.cmd(string.format("terminal az pipelines runs list --organization %s --project %s", org, project))
    end)
  end)
end

---Setup Azure Pipelines features
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("AzurePipelinesValidate", function()
    M.validate_pipeline()
  end, { desc = "Validate Azure Pipeline" })

  vim.api.nvim_create_user_command("AzurePipelinesRun", function()
    M.run_pipeline()
  end, { desc = "Run Azure Pipeline" })

  vim.api.nvim_create_user_command("AzurePipelinesRuns", function()
    M.view_pipeline_runs()
  end, { desc = "View pipeline runs" })

  vim.notify("Azure Pipelines support loaded", vim.log.levels.DEBUG)
end

return M
