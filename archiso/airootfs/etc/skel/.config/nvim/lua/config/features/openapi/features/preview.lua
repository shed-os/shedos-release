-- ═══════════════════════════════════════════════════════════
--                   OPENAPI PREVIEW FEATURES
-- ═══════════════════════════════════════════════════════════
--
-- Live preview of OpenAPI specs in:
-- 1. External browser (Swagger UI / ReDoc) with hot reload
-- 2. Floating window with rendered markdown
-- 3. Split view (YAML + preview side-by-side)
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Track running preview servers
M.servers = {}

---Check if a command exists
---@param cmd string Command to check
---@return boolean available True if command is available
local function command_exists(cmd)
  return vim.fn.executable(cmd) == 1
end

---Get free port for preview server
---@return number port Available port number
local function get_free_port()
  -- Try common ports first
  local common_ports = { 8080, 3000, 8000, 8888, 9090 }

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

  -- Fallback: random port
  return math.random(8000, 9000)
end

---Start Swagger UI preview server
---@param file_path string Path to OpenAPI file
---@param opts table|nil Options (port, ui_type)
---@return number|nil job_id Job ID or nil on failure
function M.start_swagger_preview(file_path, opts)
  opts = opts or {}
  local port = opts.port or get_free_port()
  local ui_type = opts.ui_type or "swagger" -- "swagger" or "redoc"

  -- Check if npx is available (preferred method)
  if command_exists("npx") then
    local cmd

    if ui_type == "redoc" then
      -- ReDoc (cleaner, more modern UI)
      cmd = string.format(
        "npx -y redoc-cli serve '%s' --watch --port %d 2>&1",
        file_path,
        port
      )
    else
      -- Swagger UI (more feature-rich)
      cmd = string.format(
        "npx -y swagger-ui-watcher '%s' -p %d 2>&1",
        file_path,
        port
      )
    end

    local job_id = vim.fn.jobstart(cmd, {
      on_stdout = function(_, data)
        if data and #data > 0 then
          for _, line in ipairs(data) do
            if line:match("Server started") or line:match("Listening") or line:match("http://") then
              vim.notify(
                string.format("%s preview available at: http://localhost:%d", ui_type == "redoc" and "ReDoc" or "Swagger UI", port),
                vim.log.levels.INFO
              )
              vim.schedule(function()
                M.open_browser(string.format("http://localhost:%d", port))
              end)
            end
          end
        end
      end,
      on_stderr = function(_, data)
        if data and #data > 0 then
          for _, line in ipairs(data) do
            if not line:match("^%s*$") and not line:match("npm WARN") then
              vim.notify(line, vim.log.levels.WARN)
            end
          end
        end
      end,
      on_exit = function(_, exit_code)
        M.servers[file_path] = nil
        if exit_code ~= 0 and exit_code ~= 143 then -- 143 = SIGTERM (normal stop)
          vim.notify(
            string.format("Preview server stopped with code %d", exit_code),
            vim.log.levels.WARN
          )
        end
      end,
    })

    if job_id > 0 then
      M.servers[file_path] = { job_id = job_id, port = port, ui_type = ui_type }
      vim.notify(
        string.format("Starting %s preview server on port %d...", ui_type == "redoc" and "ReDoc" or "Swagger UI", port),
        vim.log.levels.INFO
      )
      return job_id
    else
      vim.notify("Failed to start preview server", vim.log.levels.ERROR)
      return nil
    end
  elseif command_exists("python3") then
    -- Fallback: Simple Python HTTP server with basic HTML
    local html_file = vim.fn.tempname() .. ".html"
    M.generate_simple_preview_html(file_path, html_file)

    local cmd = string.format("cd '%s' && python3 -m http.server %d 2>&1", vim.fn.fnamemodify(html_file, ":h"), port)

    local job_id = vim.fn.jobstart(cmd, {
      on_exit = function()
        M.servers[file_path] = nil
        vim.fn.delete(html_file)
      end,
    })

    if job_id > 0 then
      M.servers[file_path] = { job_id = job_id, port = port, ui_type = "simple" }
      vim.notify(
        string.format("Preview server started at: http://localhost:%d/%s", port, vim.fn.fnamemodify(html_file, ":t")),
        vim.log.levels.INFO
      )
      vim.defer_fn(function()
        M.open_browser(string.format("http://localhost:%d/%s", port, vim.fn.fnamemodify(html_file, ":t")))
      end, 1000)
      return job_id
    end
  else
    vim.notify(
      "Preview requires npx or python3. Install Node.js: https://nodejs.org/",
      vim.log.levels.ERROR
    )
    return nil
  end
end

---Generate simple HTML preview (fallback)
---@param openapi_file string Path to OpenAPI file
---@param html_file string Output HTML path
function M.generate_simple_preview_html(openapi_file, html_file)
  local html_content = string.format(
    [[
<!DOCTYPE html>
<html>
<head>
  <title>OpenAPI Preview</title>
  <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui.css" />
</head>
<body>
  <div id="swagger-ui"></div>
  <script src="https://cdn.jsdelivr.net/npm/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
  <script>
    window.onload = function() {
      fetch('file://%s')
        .then(res => res.text())
        .then(spec => {
          SwaggerUIBundle({
            spec: YAML.parse(spec),
            dom_id: '#swagger-ui',
            deepLinking: true,
            presets: [
              SwaggerUIBundle.presets.apis,
              SwaggerUIBundle.SwaggerUIStandalonePreset
            ],
          });
        });
    };
  </script>
  <script src="https://cdn.jsdelivr.net/npm/js-yaml@4/dist/js-yaml.min.js"></script>
</body>
</html>
]],
    openapi_file
  )

  local file = io.open(html_file, "w")
  if file then
    file:write(html_content)
    file:close()
  end
end

---Stop preview server for file
---@param file_path string|nil Path to OpenAPI file (nil = current buffer)
function M.stop_preview(file_path)
  file_path = file_path or vim.api.nvim_buf_get_name(0)

  local server = M.servers[file_path]
  if server then
    vim.fn.jobstop(server.job_id)
    M.servers[file_path] = nil
    vim.notify(
      string.format("Stopped preview server on port %d", server.port),
      vim.log.levels.INFO
    )
  else
    vim.notify("No preview server running for this file", vim.log.levels.WARN)
  end
end

---Toggle preview server
---@param opts table|nil Options
function M.toggle_preview(opts)
  opts = opts or {}
  local file_path = vim.api.nvim_buf_get_name(0)

  if M.servers[file_path] then
    M.stop_preview(file_path)
  else
    M.start_swagger_preview(file_path, opts)
  end
end

---Open URL in default browser
---@param url string URL to open
function M.open_browser(url)
  local open_cmd

  if vim.fn.has("mac") == 1 then
    open_cmd = "open"
  elseif vim.fn.has("unix") == 1 then
    open_cmd = "xdg-open"
  elseif vim.fn.has("win32") == 1 then
    open_cmd = "start"
  else
    vim.notify("Cannot detect OS to open browser", vim.log.levels.ERROR)
    return
  end

  vim.fn.jobstart(string.format("%s '%s'", open_cmd, url), { detach = true })
end

---Show floating window preview
---@param opts table|nil Options
function M.show_floating_preview(opts)
  opts = opts or {}
  local file_path = vim.api.nvim_buf_get_name(0)

  -- Read OpenAPI content
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local content = table.concat(lines, "\n")

  -- Create preview content (simplified markdown representation)
  local preview_lines = M.generate_markdown_preview(content)

  -- Create floating window
  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, preview_lines)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " OpenAPI Preview ",
    title_pos = "center",
  })

  -- Close on 'q' or <Esc>
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

---Generate markdown preview from OpenAPI content
---@param content string OpenAPI YAML/JSON content
---@return string[] lines Markdown preview lines
function M.generate_markdown_preview(content)
  -- This is a simplified preview
  -- For production, you'd parse the YAML/JSON and create a structured preview
  local lines = { "# OpenAPI Specification Preview", "", "**Note**: Full parsing coming soon!", "", "```yaml" }

  for line in content:gmatch("[^\r\n]+") do
    table.insert(lines, line)
  end

  table.insert(lines, "```")

  return lines
end

---Setup preview features
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("OpenAPIPreview", function(args)
    local ui_type = args.args ~= "" and args.args or "swagger"
    M.start_swagger_preview(vim.api.nvim_buf_get_name(0), { ui_type = ui_type })
  end, {
    nargs = "?",
    complete = function()
      return { "swagger", "redoc" }
    end,
    desc = "Start OpenAPI preview server (swagger or redoc)",
  })

  vim.api.nvim_create_user_command("OpenAPIStopPreview", function()
    M.stop_preview()
  end, { desc = "Stop OpenAPI preview server" })

  vim.api.nvim_create_user_command("OpenAPIFloatingPreview", function()
    M.show_floating_preview()
  end, { desc = "Show OpenAPI preview in floating window" })

  vim.notify("OpenAPI preview features loaded", vim.log.levels.DEBUG)
end

return M
