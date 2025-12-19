-- ═══════════════════════════════════════════════════════════
--                OPENAPI VALIDATION & LINTING
-- ═══════════════════════════════════════════════════════════
--
-- Advanced OpenAPI validation using Spectral
-- Supports custom rulesets and style guides
--
-- ═══════════════════════════════════════════════════════════

local M = {}

---Check if spectral CLI is available
---@return boolean available True if spectral is available
local function is_spectral_available()
  return vim.fn.executable("spectral") == 1
end

---Validate OpenAPI spec using Spectral
---@param file_path string|nil Path to OpenAPI file (nil = current buffer)
---@param opts table|nil Options (format, ruleset)
function M.validate(file_path, opts)
  file_path = file_path or vim.api.nvim_buf_get_name(0)
  opts = opts or {}

  if not is_spectral_available() then
    vim.notify(
      "Spectral not found. Install with: npm install -g @stoplight/spectral-cli",
      vim.log.levels.WARN
    )
    -- Fallback to basic YAML validation
    M.validate_basic(file_path)
    return
  end

  local format = opts.format or "stylish"
  local cmd = string.format("spectral lint '%s' --format %s", file_path, format)

  -- Add custom ruleset if specified
  if opts.ruleset then
    cmd = cmd .. string.format(" --ruleset '%s'", opts.ruleset)
  end

  vim.notify("Validating OpenAPI spec with Spectral...", vim.log.levels.INFO)

  local output = {}

  vim.fn.jobstart(cmd, {
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
      if exit_code == 0 then
        vim.notify("✓ OpenAPI spec is valid!", vim.log.levels.INFO)
      else
        -- Show validation errors in quickfix
        M.show_validation_results(output)

        vim.notify(
          string.format("✗ OpenAPI spec has %d issue(s). See quickfix list.", #output),
          vim.log.levels.WARN
        )
      end
    end,
  })
end

---Show validation results in quickfix list
---@param output table Lines of spectral output
function M.show_validation_results(output)
  local qf_list = {}

  for _, line in ipairs(output) do
    -- Parse Spectral output format
    -- Format: "path/to/file:line:col  severity  rule-name  message"
    local file, lnum, col, severity, message = line:match("([^:]+):(%d+):(%d+)%s+(%w+)%s+(.+)")

    if file and lnum then
      table.insert(qf_list, {
        filename = file,
        lnum = tonumber(lnum),
        col = tonumber(col),
        type = severity == "error" and "E" or severity == "warning" and "W" or "I",
        text = message,
      })
    end
  end

  if #qf_list > 0 then
    vim.fn.setqflist(qf_list, "r")
    vim.cmd("copen")
  end
end

---Basic YAML validation (fallback when Spectral not available)
---@param file_path string Path to OpenAPI file
function M.validate_basic(file_path)
  -- Try using yq or python for basic YAML validation
  local validators = {
    { cmd = "yq", args = "eval '%s' > /dev/null" },
    { cmd = "python3", args = "-c 'import yaml; yaml.safe_load(open(\"%s\"))'" },
  }

  for _, validator in ipairs(validators) do
    if vim.fn.executable(validator.cmd) == 1 then
      local cmd = string.format(validator.args, file_path)
      local result = vim.fn.system(string.format("%s %s", validator.cmd, cmd))

      if vim.v.shell_error == 0 then
        vim.notify("✓ YAML syntax is valid (basic check)", vim.log.levels.INFO)
      else
        vim.notify(
          string.format("✗ YAML validation failed:\n%s", result),
          vim.log.levels.ERROR
        )
      end
      return
    end
  end

  vim.notify("No YAML validator found. Install spectral, yq, or python3", vim.log.levels.WARN)
end

---Create default Spectral ruleset
---@param project_root string Project root directory
function M.create_default_ruleset(project_root)
  local ruleset_path = project_root .. "/.spectral.yaml"

  if vim.fn.filereadable(ruleset_path) == 1 then
    vim.notify("Spectral ruleset already exists: " .. ruleset_path, vim.log.levels.INFO)
    return
  end

  local ruleset_content = [[
extends: [[spectral:oas, all]]

rules:
  # OpenAPI 3.x rules
  oas3-api-servers: error
  oas3-examples-value-or-externalValue: warn
  oas3-operation-security-defined: error
  oas3-parameter-description: warn
  oas3-schema-examples: warn
  oas3-server-not-example.com: error
  oas3-valid-media-example: error
  oas3-valid-schema-example: error

  # General OpenAPI rules
  operation-description: warn
  operation-operationId: error
  operation-operationId-unique: error
  operation-operationId-valid-in-url: error
  operation-parameters: error
  operation-success-response: error
  operation-tags: warn
  operation-tag-defined: error

  # Documentation rules
  info-contact: warn
  info-description: warn
  info-license: warn
  license-url: warn
  tag-description: off

  # Custom rules
  no-eval-in-markdown: error
  no-script-tags-in-markdown: error
  openapi-tags-alphabetical: off
  path-declarations-must-exist: error
  path-keys-no-trailing-slash: error
  path-not-include-query: error
  path-params-defined: error
]]

  local file = io.open(ruleset_path, "w")
  if file then
    file:write(ruleset_content)
    file:close()
    vim.notify("Created Spectral ruleset: " .. ruleset_path, vim.log.levels.INFO)
  else
    vim.notify("Failed to create Spectral ruleset", vim.log.levels.ERROR)
  end
end

---Lint OpenAPI spec and show results
---@param file_path string|nil Path to OpenAPI file (nil = current buffer)
function M.lint(file_path)
  M.validate(file_path, { format = "stylish" })
end

---Validate with JSON output (for programmatic use)
---@param file_path string|nil Path to OpenAPI file (nil = current buffer)
---@param callback function Callback function(results)
function M.validate_json(file_path, callback)
  file_path = file_path or vim.api.nvim_buf_get_name(0)

  if not is_spectral_available() then
    vim.notify("Spectral not available", vim.log.levels.ERROR)
    return
  end

  local cmd = string.format("spectral lint '%s' --format json", file_path)
  local output = ""

  vim.fn.jobstart(cmd, {
    on_stdout = function(_, data)
      if data then
        output = output .. table.concat(data, "\n")
      end
    end,
    on_exit = function(_, exit_code)
      if callback then
        local ok, results = pcall(vim.json.decode, output)
        if ok then
          callback(results)
        else
          callback(nil, "Failed to parse JSON output")
        end
      end
    end,
  })
end

---Show validation statistics
---@param file_path string|nil Path to OpenAPI file (nil = current buffer)
function M.show_stats(file_path)
  M.validate_json(file_path, function(results, err)
    if err then
      vim.notify("Failed to get validation stats: " .. err, vim.log.levels.ERROR)
      return
    end

    if not results then
      vim.notify("✓ No validation issues found", vim.log.levels.INFO)
      return
    end

    local stats = {
      errors = 0,
      warnings = 0,
      info = 0,
      hints = 0,
    }

    for _, result in ipairs(results) do
      local severity = result.severity
      if severity == 0 then
        stats.errors = stats.errors + 1
      elseif severity == 1 then
        stats.warnings = stats.warnings + 1
      elseif severity == 2 then
        stats.info = stats.info + 1
      else
        stats.hints = stats.hints + 1
      end
    end

    local message = string.format(
      "OpenAPI Validation Stats:\n  Errors: %d\n  Warnings: %d\n  Info: %d\n  Hints: %d",
      stats.errors,
      stats.warnings,
      stats.info,
      stats.hints
    )

    vim.notify(message, stats.errors > 0 and vim.log.levels.ERROR or vim.log.levels.INFO)
  end)
end

---Setup validation features
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("OpenAPIValidate", function()
    M.validate()
  end, { desc = "Validate OpenAPI spec with Spectral" })

  vim.api.nvim_create_user_command("OpenAPILint", function()
    M.lint()
  end, { desc = "Lint OpenAPI spec" })

  vim.api.nvim_create_user_command("OpenAPIValidateStats", function()
    M.show_stats()
  end, { desc = "Show OpenAPI validation statistics" })

  vim.api.nvim_create_user_command("OpenAPICreateRuleset", function()
    local project_root = vim.fn.getcwd()
    M.create_default_ruleset(project_root)
  end, { desc = "Create default Spectral ruleset" })

  vim.notify("OpenAPI validation features loaded", vim.log.levels.DEBUG)
end

return M
