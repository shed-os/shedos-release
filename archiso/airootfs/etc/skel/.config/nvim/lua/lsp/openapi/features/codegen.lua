-- ═══════════════════════════════════════════════════════════
--                OPENAPI CODE GENERATION
-- ═══════════════════════════════════════════════════════════
--
-- Generate client SDKs and server stubs from OpenAPI specs
-- Supports: Java, Kotlin, TypeScript, JavaScript, Python, Go,
--           Rust, and many more via openapi-generator
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Available generators (commonly used ones)
M.generators = {
  -- Client generators
  clients = {
    { name = "java", desc = "Java client (native, OkHttp, RestTemplate)" },
    { name = "kotlin", desc = "Kotlin client" },
    { name = "typescript-fetch", desc = "TypeScript/JavaScript (fetch API)" },
    { name = "typescript-axios", desc = "TypeScript/JavaScript (axios)" },
    { name = "javascript", desc = "JavaScript (ES6)" },
    { name = "python", desc = "Python client" },
    { name = "go", desc = "Go client" },
    { name = "rust", desc = "Rust client (reqwest)" },
    { name = "csharp", desc = "C# client (.NET)" },
    { name = "php", desc = "PHP client" },
    { name = "ruby", desc = "Ruby client" },
    { name = "swift5", desc = "Swift 5 client (iOS/macOS)" },
    { name = "dart", desc = "Dart client (Flutter)" },
  },

  -- Server generators
  servers = {
    { name = "spring", desc = "Spring Boot (Java)" },
    { name = "kotlin-spring", desc = "Spring Boot (Kotlin)" },
    { name = "nodejs-express-server", desc = "Node.js Express" },
    { name = "typescript-nestjs", desc = "NestJS (TypeScript)" },
    { name = "python-flask", desc = "Python Flask" },
    { name = "python-fastapi", desc = "Python FastAPI" },
    { name = "go-server", desc = "Go server (net/http)" },
    { name = "go-gin-server", desc = "Go Gin server" },
    { name = "rust-server", desc = "Rust server (Actix)" },
    { name = "aspnetcore", desc = "ASP.NET Core (C#)" },
    { name = "php-laravel", desc = "Laravel (PHP)" },
    { name = "ruby-on-rails", desc = "Ruby on Rails" },
  },
}

---Check if openapi-generator is available
---@return boolean available True if available
---@return string|nil install_cmd Installation command if not available
local function check_generator_available()
  -- Check for npx (easiest method)
  if vim.fn.executable("npx") == 1 then
    return true, nil
  end

  -- Check for docker (alternative method)
  if vim.fn.executable("docker") == 1 then
    return true, nil
  end

  -- Check for jar file (manual installation)
  if vim.fn.executable("openapi-generator-cli") == 1 then
    return true, nil
  end

  return false, "npm install -g @openapitools/openapi-generator-cli"
end

---Get openapi-generator command
---@return string|nil cmd Command to use, or nil if not available
local function get_generator_cmd()
  if vim.fn.executable("npx") == 1 then
    return "npx -y @openapitools/openapi-generator-cli"
  elseif vim.fn.executable("docker") == 1 then
    return "docker run --rm -v ${PWD}:/local openapitools/openapi-generator-cli"
  elseif vim.fn.executable("openapi-generator-cli") == 1 then
    return "openapi-generator-cli"
  end
  return nil
end

---List available generators
---@param type string "client" or "server"
---@return table generators List of generators
function M.list_generators(type)
  if type == "client" then
    return M.generators.clients
  elseif type == "server" then
    return M.generators.servers
  else
    -- Return all
    local all = {}
    vim.list_extend(all, M.generators.clients)
    vim.list_extend(all, M.generators.servers)
    return all
  end
end

---Generate code from OpenAPI spec
---@param spec_file string Path to OpenAPI spec file
---@param generator string Generator name (e.g., "spring", "typescript-axios")
---@param output_dir string Output directory
---@param opts table|nil Additional options
function M.generate(spec_file, generator, output_dir, opts)
  opts = opts or {}

  local available, install_cmd = check_generator_available()
  if not available then
    vim.notify(
      string.format("openapi-generator not found. Install with: %s", install_cmd),
      vim.log.levels.ERROR
    )
    return
  end

  local cmd = get_generator_cmd()
  if not cmd then
    vim.notify("Failed to get openapi-generator command", vim.log.levels.ERROR)
    return
  end

  -- Build generation command
  local gen_cmd = string.format(
    "%s generate -i '%s' -g %s -o '%s'",
    cmd,
    spec_file,
    generator,
    output_dir
  )

  -- Add package name if specified
  if opts.package_name then
    gen_cmd = gen_cmd .. string.format(" --package-name %s", opts.package_name)
  end

  -- Add additional properties
  if opts.additional_properties then
    local props = {}
    for k, v in pairs(opts.additional_properties) do
      table.insert(props, string.format("%s=%s", k, v))
    end
    if #props > 0 then
      gen_cmd = gen_cmd .. string.format(" --additional-properties=%s", table.concat(props, ","))
    end
  end

  vim.notify(
    string.format("Generating %s code to %s...", generator, output_dir),
    vim.log.levels.INFO
  )

  -- Execute generation
  vim.fn.jobstart(gen_cmd, {
    on_stdout = function(_, data)
      if data and #data > 0 then
        for _, line in ipairs(data) do
          if not line:match("^%s*$") then
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
      if exit_code == 0 then
        vim.notify(
          string.format("✓ Code generation complete! Output: %s", output_dir),
          vim.log.levels.INFO
        )
      else
        vim.notify(
          string.format("Code generation failed with exit code %d", exit_code),
          vim.log.levels.ERROR
        )
      end
    end,
  })
end

---Interactive code generation with prompts
---@param spec_file string|nil Path to OpenAPI spec (nil = current buffer)
function M.generate_interactive(spec_file)
  spec_file = spec_file or vim.api.nvim_buf_get_name(0)

  -- Step 1: Choose client or server
  vim.ui.select({ "Client SDK", "Server Stub" }, {
    prompt = "Generate:",
  }, function(choice)
    if not choice then
      return
    end

    local generator_type = choice:match("Client") and "client" or "server"

    -- Step 2: Choose specific generator
    local generators = M.list_generators(generator_type)
    local generator_names = vim.tbl_map(function(g)
      return string.format("%s - %s", g.name, g.desc)
    end, generators)

    vim.ui.select(generator_names, {
      prompt = string.format("Select %s generator:", choice),
    }, function(selected)
      if not selected then
        return
      end

      local generator = selected:match("^([^%s]+)")

      -- Step 3: Choose output directory
      vim.ui.input({
        prompt = "Output directory: ",
        default = vim.fn.getcwd() .. "/generated",
      }, function(output_dir)
        if not output_dir or output_dir == "" then
          return
        end

        -- Step 4: Optional package name (for Java/Kotlin)
        if generator:match("java") or generator:match("kotlin") or generator:match("spring") then
          vim.ui.input({
            prompt = "Package name (optional): ",
            default = "com.example.api",
          }, function(package_name)
            local opts = {}
            if package_name and package_name ~= "" then
              opts.package_name = package_name
            end

            M.generate(spec_file, generator, output_dir, opts)
          end)
        else
          M.generate(spec_file, generator, output_dir)
        end
      end)
    end)
  end)
end

---Generate client SDK (quick command)
---@param lang string Language/generator name
---@param spec_file string|nil Path to spec (nil = current buffer)
function M.generate_client(lang, spec_file)
  spec_file = spec_file or vim.api.nvim_buf_get_name(0)
  local output_dir = vim.fn.getcwd() .. "/generated-client"

  M.generate(spec_file, lang, output_dir)
end

---Generate server stub (quick command)
---@param lang string Language/generator name
---@param spec_file string|nil Path to spec (nil = current buffer)
function M.generate_server(lang, spec_file)
  spec_file = spec_file or vim.api.nvim_buf_get_name(0)
  local output_dir = vim.fn.getcwd() .. "/generated-server"

  M.generate(spec_file, lang, output_dir)
end

---Show help for code generation
function M.show_help()
  local lines = {
    "# OpenAPI Code Generation",
    "",
    "## Available Commands:",
    "- `:OpenAPIGenerate` - Interactive code generation wizard",
    "- `:OpenAPIGenerateClient <lang>` - Quick client generation",
    "- `:OpenAPIGenerateServer <lang>` - Quick server generation",
    "",
    "## Common Languages:",
    "",
    "### Clients:",
  }

  for _, gen in ipairs(M.generators.clients) do
    table.insert(lines, string.format("  - `%s`: %s", gen.name, gen.desc))
  end

  table.insert(lines, "")
  table.insert(lines, "### Servers:")

  for _, gen in ipairs(M.generators.servers) do
    table.insert(lines, string.format("  - `%s`: %s", gen.name, gen.desc))
  end

  table.insert(lines, "")
  table.insert(lines, "## Examples:")
  table.insert(lines, "```")
  table.insert(lines, ":OpenAPIGenerateClient typescript-axios")
  table.insert(lines, ":OpenAPIGenerateServer spring")
  table.insert(lines, "```")

  -- Show in floating window
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_set_option_value("filetype", "markdown", { buf = buf })
  vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

  local width = math.min(80, vim.o.columns - 4)
  local height = math.min(#lines + 2, vim.o.lines - 4)

  vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2),
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " OpenAPI Code Generation Help ",
    title_pos = "center",
  })

  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = buf, silent = true })
end

---Setup code generation features
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("OpenAPIGenerate", function()
    M.generate_interactive()
  end, { desc = "Generate code from OpenAPI spec (interactive)" })

  vim.api.nvim_create_user_command("OpenAPIGenerateClient", function(args)
    if args.args == "" then
      vim.notify("Usage: :OpenAPIGenerateClient <language>", vim.log.levels.ERROR)
      return
    end
    M.generate_client(args.args)
  end, {
    nargs = 1,
    complete = function()
      return vim.tbl_map(function(g)
        return g.name
      end, M.generators.clients)
    end,
    desc = "Generate client SDK from OpenAPI spec",
  })

  vim.api.nvim_create_user_command("OpenAPIGenerateServer", function(args)
    if args.args == "" then
      vim.notify("Usage: :OpenAPIGenerateServer <language>", vim.log.levels.ERROR)
      return
    end
    M.generate_server(args.args)
  end, {
    nargs = 1,
    complete = function()
      return vim.tbl_map(function(g)
        return g.name
      end, M.generators.servers)
    end,
    desc = "Generate server stub from OpenAPI spec",
  })

  vim.api.nvim_create_user_command("OpenAPIGenerateHelp", function()
    M.show_help()
  end, { desc = "Show OpenAPI code generation help" })

  vim.notify("OpenAPI code generation features loaded", vim.log.levels.DEBUG)
end

return M
