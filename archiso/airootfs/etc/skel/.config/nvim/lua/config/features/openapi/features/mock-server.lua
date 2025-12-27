-- ═══════════════════════════════════════════════════════════
--                  OPENAPI MOCK SERVER
-- ═══════════════════════════════════════════════════════════
--
-- Start mock API servers from OpenAPI specs using Prism
-- Test your API clients without a real backend
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Track running mock servers
M.mock_servers = {}

---Check if prism is available
---@return boolean available True if prism is available
---@return string|nil install_cmd Installation command if not available
local function is_prism_available()
  if vim.fn.executable("prism") == 1 then
    return true, nil
  end

  if vim.fn.executable("npx") == 1 then
    return true, nil
  end

  if vim.fn.executable("docker") == 1 then
    return true, nil
  end

  return false, "npm install -g @stoplight/prism-cli"
end

---Get prism command
---@return string|nil cmd Command to use
local function get_prism_cmd()
  if vim.fn.executable("prism") == 1 then
    return "prism"
  elseif vim.fn.executable("npx") == 1 then
    return "npx -y @stoplight/prism-cli"
  elseif vim.fn.executable("docker") == 1 then
    return "docker run --rm -v ${PWD}:/tmp -p 4010:4010 stoplight/prism"
  end
  return nil
end

---Get free port for mock server
---@return number port Available port
local function get_free_port()
  local common_ports = { 4010, 8080, 3000, 8000 }

  for _, port in ipairs(common_ports) do
    local handle = io.popen(string.format("lsof -i:%d 2>/dev/null", port))
    if handle then
      local result = handle:read("*a")
      handle:close()
      if result == "" then
        return port
      end
    end
  end

  return math.random(4000, 5000)
end

---Start mock server for OpenAPI spec
---@param spec_file string Path to OpenAPI spec file
---@param opts table|nil Options (port, host, dynamic, validate)
---@return number|nil job_id Job ID or nil on failure
function M.start_mock_server(spec_file, opts)
  opts = opts or {}
  local port = opts.port or get_free_port()
  local host = opts.host or "127.0.0.1"
  local dynamic = opts.dynamic ~= false -- Default true
  local validate = opts.validate ~= false -- Default true

  local available, install_cmd = is_prism_available()
  if not available then
    vim.notify(
      string.format("Prism not found. Install with: %s", install_cmd),
      vim.log.levels.ERROR
    )
    return nil
  end

  local cmd = get_prism_cmd()
  if not cmd then
    vim.notify("Failed to get Prism command", vim.log.levels.ERROR)
    return nil
  end

  -- Build mock command
  local mock_cmd = string.format(
    "%s mock '%s' --host %s --port %d",
    cmd,
    spec_file,
    host,
    port
  )

  -- Add options
  if dynamic then
    mock_cmd = mock_cmd .. " --dynamic"
  end

  if not validate then
    mock_cmd = mock_cmd .. " --no-validate"
  end

  vim.notify(
    string.format("Starting mock API server on http://%s:%d...", host, port),
    vim.log.levels.INFO
  )

  local job_id = vim.fn.jobstart(mock_cmd, {
    on_stdout = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if line:match("Prism is listening") or line:match("http://") then
            vim.notify(
              string.format("✓ Mock API server running at: http://%s:%d", host, port),
              vim.log.levels.INFO
            )
          elseif not line:match("^%s*$") then
            vim.notify(line, vim.log.levels.DEBUG)
          end
        end
      end
    end,
    on_stderr = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if not line:match("^%s*$") and not line:match("WARN") then
            vim.notify(line, vim.log.levels.WARN)
          end
        end
      end
    end,
    on_exit = function(_, exit_code)
      M.mock_servers[spec_file] = nil
      if exit_code ~= 0 and exit_code ~= 143 then
        vim.notify(
          string.format("Mock server stopped with exit code %d", exit_code),
          vim.log.levels.WARN
        )
      end
    end,
  })

  if job_id > 0 then
    M.mock_servers[spec_file] = {
      job_id = job_id,
      port = port,
      host = host,
      url = string.format("http://%s:%d", host, port),
    }
    return job_id
  else
    vim.notify("Failed to start mock server", vim.log.levels.ERROR)
    return nil
  end
end

---Stop mock server for spec file
---@param spec_file string|nil Path to OpenAPI spec (nil = current buffer)
function M.stop_mock_server(spec_file)
  spec_file = spec_file or vim.api.nvim_buf_get_name(0)

  local server = M.mock_servers[spec_file]
  if server then
    vim.fn.jobstop(server.job_id)
    M.mock_servers[spec_file] = nil
    vim.notify(
      string.format("Stopped mock server on port %d", server.port),
      vim.log.levels.INFO
    )
  else
    vim.notify("No mock server running for this file", vim.log.levels.WARN)
  end
end

---Toggle mock server
---@param opts table|nil Options
function M.toggle_mock_server(opts)
  local spec_file = vim.api.nvim_buf_get_name(0)

  if M.mock_servers[spec_file] then
    M.stop_mock_server(spec_file)
  else
    M.start_mock_server(spec_file, opts)
  end
end

---Get mock server URL for current spec
---@return string|nil url Mock server URL or nil
function M.get_mock_url()
  local spec_file = vim.api.nvim_buf_get_name(0)
  local server = M.mock_servers[spec_file]

  if server then
    return server.url
  end

  return nil
end

---Test endpoint using mock server
---@param endpoint string Endpoint path (e.g., "/api/users")
---@param method string HTTP method (GET, POST, etc.)
function M.test_endpoint(endpoint, method)
  local url = M.get_mock_url()
  if not url then
    vim.notify("No mock server running. Start one first with :OpenAPIMockStart", vim.log.levels.WARN)
    return
  end

  method = method or "GET"
  local test_url = url .. endpoint

  -- Use curl to test
  if vim.fn.executable("curl") == 1 then
    local cmd = string.format("curl -X %s '%s' -i", method, test_url)

    vim.notify(string.format("Testing: %s %s", method, test_url), vim.log.levels.INFO)

    local output = {}
    vim.fn.jobstart(cmd, {
      on_stdout = function(_, data)
        if data then
          vim.list_extend(output, data)
        end
      end,
      on_exit = function(_, exit_code)
        if exit_code == 0 then
          -- Show response in floating window
          M.show_response(output)
        else
          vim.notify("Request failed", vim.log.levels.ERROR)
        end
      end,
    })
  else
    vim.notify("curl not found. Cannot test endpoint.", vim.log.levels.ERROR)
  end
end

---Show HTTP response in floating window
---@param response table Response lines
function M.show_response(response)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, response)
  vim.api.nvim_set_option_value("filetype", "http", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local width = math.min(100, vim.o.columns - 4)
  local height = math.min(#response + 2, vim.o.lines - 4)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Mock API Response ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

---List all running mock servers
function M.list_servers()
  if vim.tbl_count(M.mock_servers) == 0 then
    vim.notify("No mock servers running", vim.log.levels.INFO)
    return
  end

  local lines = { "# Running Mock Servers", "" }

  for spec_file, server in pairs(M.mock_servers) do
    table.insert(lines, string.format("- %s", vim.fn.fnamemodify(spec_file, ":t")))
    table.insert(lines, string.format("  URL: %s", server.url))
    table.insert(lines, string.format("  Job: %d", server.job_id))
    table.insert(lines, "")
  end

  -- Show in floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local width = math.min(60, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " Mock Servers ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

---Stop all mock servers
function M.stop_all_servers()
  local count = 0
  for spec_file, _ in pairs(M.mock_servers) do
    M.stop_mock_server(spec_file)
    count = count + 1
  end

  if count > 0 then
    vim.notify(string.format("Stopped %d mock server(s)", count), vim.log.levels.INFO)
  else
    vim.notify("No mock servers were running", vim.log.levels.INFO)
  end
end

---Setup mock server features
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("OpenAPIMockStart", function()
    M.start_mock_server(vim.api.nvim_buf_get_name(0))
  end, { desc = "Start mock API server from OpenAPI spec" })

  vim.api.nvim_create_user_command("OpenAPIMockStop", function()
    M.stop_mock_server()
  end, { desc = "Stop mock API server" })

  vim.api.nvim_create_user_command("OpenAPIMockToggle", function()
    M.toggle_mock_server()
  end, { desc = "Toggle mock API server" })

  vim.api.nvim_create_user_command("OpenAPIMockList", function()
    M.list_servers()
  end, { desc = "List running mock servers" })

  vim.api.nvim_create_user_command("OpenAPIMockStopAll", function()
    M.stop_all_servers()
  end, { desc = "Stop all mock servers" })

  vim.api.nvim_create_user_command("OpenAPIMockTest", function(args)
    local parts = vim.split(args.args, " ")
    local endpoint = parts[1] or "/api"
    local method = parts[2] or "GET"
    M.test_endpoint(endpoint, method)
  end, {
    nargs = "*",
    desc = "Test endpoint on mock server (usage: path [method])",
  })

  vim.notify("OpenAPI mock server features loaded", vim.log.levels.DEBUG)
end

return M
