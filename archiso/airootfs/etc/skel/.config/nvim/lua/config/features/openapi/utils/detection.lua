-- ═══════════════════════════════════════════════════════════
--                    OPENAPI FILE DETECTION
-- ═══════════════════════════════════════════════════════════
--
-- Utilities to detect if a YAML/JSON file is an OpenAPI spec
--
-- ═══════════════════════════════════════════════════════════

local M = {}

---Check if current buffer is an OpenAPI specification
---@param bufnr number|nil Buffer number (default: current buffer)
---@return boolean is_openapi True if file is OpenAPI spec
---@return string|nil version OpenAPI version (e.g., "3.0.0", "2.0", nil if not OpenAPI)
function M.is_openapi_file(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- Check file name patterns first (fast path)
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local basename = vim.fn.fnamemodify(filename, ":t"):lower()

  -- Common OpenAPI file names
  local openapi_patterns = {
    "openapi%.ya?ml$",
    "openapi%.json$",
    "swagger%.ya?ml$",
    "swagger%.json$",
    "api%.ya?ml$",
    "api%-spec%.ya?ml$",
    "api%-spec%.json$",
  }

  for _, pattern in ipairs(openapi_patterns) do
    if basename:match(pattern) then
      -- Still need to verify content, but likely OpenAPI
      return M.verify_openapi_content(bufnr)
    end
  end

  -- Check file content for OpenAPI/Swagger keywords
  return M.verify_openapi_content(bufnr)
end

---Verify buffer content contains OpenAPI specification
---@param bufnr number Buffer number
---@return boolean is_openapi True if content is OpenAPI spec
---@return string|nil version OpenAPI version or nil
function M.verify_openapi_content(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 50, false) -- Check first 50 lines

  for _, line in ipairs(lines) do
    -- OpenAPI 3.x detection
    if line:match("^%s*openapi%s*:%s*['\"]?3%.") then
      local version = line:match("openapi%s*:%s*['\"]?([%d%.]+)")
      return true, version
    end

    -- Swagger 2.0 detection
    if line:match("^%s*swagger%s*:%s*['\"]?2%.") then
      local version = line:match("swagger%s*:%s*['\"]?([%d%.]+)")
      return true, version
    end

    -- JSON format detection
    if line:match('"openapi"%s*:%s*"3%.') then
      local version = line:match('"openapi"%s*:%s*"([%d%.]+)"')
      return true, version
    end

    if line:match('"swagger"%s*:%s*"2%.') then
      local version = line:match('"swagger"%s*:%s*"([%d%.]+)"')
      return true, version
    end
  end

  return false, nil
end

---Get OpenAPI specification version from buffer
---@param bufnr number|nil Buffer number (default: current buffer)
---@return string|nil version OpenAPI version or nil
function M.get_openapi_version(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local _, version = M.is_openapi_file(bufnr)
  return version
end

---Check if OpenAPI version is 3.x
---@param bufnr number|nil Buffer number (default: current buffer)
---@return boolean is_v3 True if OpenAPI 3.x
function M.is_openapi_v3(bufnr)
  local version = M.get_openapi_version(bufnr)
  return version ~= nil and version:match("^3%.")
end

---Check if OpenAPI version is 2.0 (Swagger)
---@param bufnr number|nil Buffer number (default: current buffer)
---@return boolean is_v2 True if Swagger 2.0
function M.is_swagger_v2(bufnr)
  local version = M.get_openapi_version(bufnr)
  return version ~= nil and version:match("^2%.")
end

---Get file format (yaml or json)
---@param bufnr number|nil Buffer number (default: current buffer)
---@return string format "yaml" or "json"
function M.get_file_format(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local filetype = vim.api.nvim_get_option_value("filetype", { buf = bufnr })

  if filetype == "json" then
    return "json"
  elseif filetype == "yaml" then
    return "yaml"
  end

  -- Fallback: check file extension
  local filename = vim.api.nvim_buf_get_name(bufnr)
  if filename:match("%.json$") then
    return "json"
  end

  return "yaml" -- Default to YAML
end

---Create autocmd to detect OpenAPI files
---@param callback function Function to call when OpenAPI file is detected
function M.setup_detection_autocmd(callback)
  vim.api.nvim_create_autocmd({ "BufEnter", "BufNewFile" }, {
    pattern = { "*.yaml", "*.yml", "*.json" },
    callback = function(args)
      local is_openapi, version = M.is_openapi_file(args.buf)
      if is_openapi then
        callback(args.buf, version)
      end
    end,
    group = vim.api.nvim_create_augroup("OpenAPIDetection", { clear = true }),
  })
end

return M
