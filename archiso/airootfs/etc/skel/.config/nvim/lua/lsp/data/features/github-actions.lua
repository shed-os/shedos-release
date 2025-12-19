-- ═══════════════════════════════════════════════════════════
--                  GITHUB ACTIONS SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- LSP support and validation for GitHub Actions workflows
--
-- ═══════════════════════════════════════════════════════════

local M = {}

---Check if file is a GitHub Actions workflow
---@param bufnr number|nil Buffer number (default: current)
---@return boolean is_workflow True if GitHub Actions workflow
function M.is_github_actions_workflow(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local filepath = vim.api.nvim_buf_get_name(bufnr)

  -- Check if file is in .github/workflows/
  if filepath:match("%.github/workflows/.+%.ya?ml$") then
    return true
  end

  -- Check file content for workflow indicators
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 20, false)
  for _, line in ipairs(lines) do
    if line:match("^on:%s*$") or line:match("^%s*on:%s*$") then
      return true
    end
    if line:match("^jobs:%s*$") or line:match("^%s*jobs:%s*$") then
      return true
    end
  end

  return false
end

---Validate workflow using actionlint
---@param filepath string|nil Path to workflow file (nil = current buffer)
function M.validate_workflow(filepath)
  filepath = filepath or vim.api.nvim_buf_get_name(0)

  if vim.fn.executable("actionlint") ~= 1 then
    vim.notify(
      "actionlint not found. Install: brew install actionlint or go install github.com/rhysd/actionlint/cmd/actionlint@latest",
      vim.log.levels.WARN
    )
    return
  end

  vim.notify("Validating GitHub Actions workflow...", vim.log.levels.INFO)

  local output = {}
  vim.fn.jobstart(string.format("actionlint '%s'", filepath), {
    on_stdout = function(_, data)
      if data then
        vim.list_extend(output, data)
      end
    end,
    on_stderr = function(_, data)
      if data then
        vim.list_extend(output, data)
      end
    end,
    on_exit = function(_, exit_code)
      if exit_code == 0 and #output == 0 then
        vim.notify("✓ Workflow is valid!", vim.log.levels.INFO)
      else
        -- Show validation errors in quickfix
        local qf_list = {}

        for _, line in ipairs(output) do
          -- Parse actionlint output format
          local file, lnum, col, message = line:match("([^:]+):(%d+):(%d+): (.+)")

          if file and lnum then
            table.insert(qf_list, {
              filename = file,
              lnum = tonumber(lnum),
              col = tonumber(col),
              text = message,
              type = "E",
            })
          end
        end

        if #qf_list > 0 then
          vim.fn.setqflist(qf_list, "r")
          vim.cmd("copen")
        end

        vim.notify(string.format("✗ Found %d issue(s). See quickfix list.", #qf_list), vim.log.levels.WARN)
      end
    end,
  })
end

---Trigger workflow using gh CLI
---@param workflow_file string|nil Workflow filename (nil = current file)
function M.trigger_workflow(workflow_file)
  workflow_file = workflow_file or vim.fn.expand("%:t")

  if vim.fn.executable("gh") ~= 1 then
    vim.notify("gh CLI not found. Install from https://cli.github.com/", vim.log.levels.ERROR)
    return
  end

  -- Get branch to run on
  vim.ui.input({
    prompt = "Branch (default: main): ",
    default = "main",
  }, function(branch)
    if not branch or branch == "" then
      return
    end

    local cmd = string.format("gh workflow run '%s' --ref %s", workflow_file, branch)

    vim.fn.jobstart(cmd, {
      on_exit = function(_, exit_code)
        if exit_code == 0 then
          vim.notify("✓ Workflow triggered successfully", vim.log.levels.INFO)
        else
          vim.notify("✗ Failed to trigger workflow", vim.log.levels.ERROR)
        end
      end,
    })
  end)
end

---View workflow runs
function M.view_workflow_runs()
  if vim.fn.executable("gh") ~= 1 then
    vim.notify("gh CLI not found. Install from https://cli.github.com/", vim.log.levels.ERROR)
    return
  end

  vim.cmd("terminal gh run list")
end

---View workflow logs
---@param run_id string|nil Run ID (nil = prompt)
function M.view_workflow_logs(run_id)
  if vim.fn.executable("gh") ~= 1 then
    vim.notify("gh CLI not found. Install from https://cli.github.com/", vim.log.levels.ERROR)
    return
  end

  if not run_id then
    vim.ui.input({
      prompt = "Run ID: ",
    }, function(input)
      if input and input ~= "" then
        M.view_workflow_logs(input)
      end
    end)
    return
  end

  vim.cmd(string.format("terminal gh run view %s --log", run_id))
end

---Setup GitHub Actions features
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("GHActionsValidate", function()
    M.validate_workflow()
  end, { desc = "Validate GitHub Actions workflow" })

  vim.api.nvim_create_user_command("GHActionsTrigger", function()
    M.trigger_workflow()
  end, { desc = "Trigger GitHub Actions workflow" })

  vim.api.nvim_create_user_command("GHActionsRuns", function()
    M.view_workflow_runs()
  end, { desc = "View workflow runs" })

  vim.api.nvim_create_user_command("GHActionsLogs", function()
    M.view_workflow_logs()
  end, { desc = "View workflow logs" })

  vim.notify("GitHub Actions support loaded", vim.log.levels.DEBUG)
end

return M
