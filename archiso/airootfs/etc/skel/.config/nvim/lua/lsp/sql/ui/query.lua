-- ═══════════════════════════════════════════════════════════
--                    SQL QUERY RUNNER
-- ═══════════════════════════════════════════════════════════
--
-- Execute SQL queries directly in SQL files using vim-dadbod
-- Supports: PostgreSQL, MySQL, SQLite, SQL Server, Oracle
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Track recent queries and connections
M.recent_queries = {}
M.last_connection = nil
M.result_buffers = {}

---Check if vim-dadbod is available
---@return boolean available True if dadbod is available
local function is_dadbod_available()
  return vim.fn.exists(":DB") == 2
end

---Execute SQL query
---@param query string SQL query to execute
---@param connection string|nil Database connection URL (nil = use last or prompt)
function M.execute_query(query, connection)
  if not is_dadbod_available() then
    vim.notify("vim-dadbod not found. Install it first!", vim.log.levels.ERROR)
    return
  end

  -- Get connection if not provided
  if not connection then
    if M.last_connection then
      connection = M.last_connection
    else
      M.prompt_for_connection(function(conn)
        if conn then
          M.execute_query(query, conn)
        end
      end)
      return
    end
  end

  -- Store connection
  M.last_connection = connection

  -- Execute query using dadbod
  local cmd = string.format("DB %s %s", connection, query)

  -- Create result buffer
  local result_buf = vim.api.nvim_create_buf(false, true)
  M.result_buffers[#M.result_buffers + 1] = result_buf

  -- Execute and capture output
  local output = vim.fn.systemlist(string.format("echo %s | db %s", vim.fn.shellescape(query), vim.fn.shellescape(connection)))

  -- Show results in split
  vim.cmd("botright split")
  vim.api.nvim_set_current_buf(result_buf)
  vim.api.nvim_buf_set_lines(result_buf, 0, -1, false, output)
  vim.api.nvim_set_option_value("filetype", "dbout", { buf = result_buf })
  vim.api.nvim_set_option_value("buftype", "nofile", { buf = result_buf })
  vim.api.nvim_buf_set_name(result_buf, "DB Results")

  -- Add query to recent list
  table.insert(M.recent_queries, { query = query, connection = connection, timestamp = os.time() })

  -- Close result buffer keymap
  vim.keymap.set("n", "q", "<cmd>close<cr>", { buffer = result_buf, silent = true })
  vim.keymap.set("n", "<Esc>", "<cmd>close<cr>", { buffer = result_buf, silent = true })

  vim.notify("Query executed successfully", vim.log.levels.INFO)
end

---Execute query under cursor or visual selection
---@param connection string|nil Database connection
function M.execute_current(connection)
  local mode = vim.fn.mode()
  local query

  if mode == "v" or mode == "V" then
    -- Get visual selection
    local start_pos = vim.fn.getpos("'<")
    local end_pos = vim.fn.getpos("'>")
    local lines = vim.api.nvim_buf_get_lines(0, start_pos[2] - 1, end_pos[2], false)
    query = table.concat(lines, "\n")
  else
    -- Get query under cursor (until semicolon)
    local cursor_line = vim.fn.line(".")
    local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)

    -- Find query boundaries
    local start_line = cursor_line
    local end_line = cursor_line

    -- Search backwards for previous semicolon or start of file
    for i = cursor_line - 1, 1, -1 do
      if lines[i]:match(";%s*$") then
        start_line = i + 1
        break
      end
      if i == 1 then
        start_line = 1
      end
    end

    -- Search forwards for next semicolon
    for i = cursor_line, #lines do
      if lines[i]:match(";%s*$") then
        end_line = i
        break
      end
    end

    -- Extract query
    local query_lines = {}
    for i = start_line, end_line do
      table.insert(query_lines, lines[i])
    end
    query = table.concat(query_lines, "\n")
  end

  if query and query ~= "" then
    M.execute_query(query:gsub("^%s+", ""):gsub("%s+$", ""), connection)
  else
    vim.notify("No query found", vim.log.levels.WARN)
  end
end

---Execute entire file
---@param connection string|nil Database connection
function M.execute_file(connection)
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  local query = table.concat(lines, "\n")

  if query and query ~= "" then
    M.execute_query(query, connection)
  else
    vim.notify("File is empty", vim.log.levels.WARN)
  end
end

---Prompt for database connection
---@param callback function Callback function(connection_string)
function M.prompt_for_connection(callback)
  -- Common connection templates
  local templates = {
    "postgresql://user:password@localhost:5432/dbname",
    "mysql://user:password@localhost:3306/dbname",
    "sqlite:///path/to/database.db",
    "sqlserver://user:password@localhost:1433/dbname",
  }

  vim.ui.select(templates, {
    prompt = "Select connection template (or type custom):",
    format_item = function(item)
      return item:match("^(%w+)://")
    end,
  }, function(selected)
    if not selected then
      return
    end

    vim.ui.input({
      prompt = "Database connection URL: ",
      default = selected,
    }, function(input)
      if input and input ~= "" then
        callback(input)
      end
    end)
  end)
end

---Show recent query history
function M.show_recent_queries()
  if #M.recent_queries == 0 then
    vim.notify("No recent queries", vim.log.levels.INFO)
    return
  end

  local items = {}
  for i = #M.recent_queries, math.max(1, #M.recent_queries - 9), -1 do
    local q = M.recent_queries[i]
    local preview = q.query:gsub("\n", " "):sub(1, 50)
    table.insert(items, string.format("%s... (%s)", preview, os.date("%H:%M:%S", q.timestamp)))
  end

  vim.ui.select(items, {
    prompt = "Recent queries:",
  }, function(selected, idx)
    if selected then
      local actual_idx = #M.recent_queries - idx + 1
      local q = M.recent_queries[actual_idx]
      M.execute_query(q.query, q.connection)
    end
  end)
end

---Connect to database (store connection for later use)
function M.connect()
  M.prompt_for_connection(function(connection)
    if connection then
      M.last_connection = connection
      vim.notify("Connected to: " .. connection:match("^(%w+://[^:]+)"), vim.log.levels.INFO)
    end
  end)
end

---Open DBUI (vim-dadbod-ui)
function M.open_dbui()
  if vim.fn.exists(":DBUI") == 2 then
    vim.cmd("DBUI")
  else
    vim.notify("vim-dadbod-ui not installed", vim.log.levels.WARN)
  end
end

---Setup SQL query runner
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("SQLExecute", function()
    M.execute_current()
  end, { desc = "Execute SQL query under cursor", range = true })

  vim.api.nvim_create_user_command("SQLExecuteFile", function()
    M.execute_file()
  end, { desc = "Execute entire SQL file" })

  vim.api.nvim_create_user_command("SQLConnect", function()
    M.connect()
  end, { desc = "Connect to database" })

  vim.api.nvim_create_user_command("SQLRecent", function()
    M.show_recent_queries()
  end, { desc = "Show recent queries" })

  vim.notify("SQL query runner loaded", vim.log.levels.DEBUG)
end

return M
