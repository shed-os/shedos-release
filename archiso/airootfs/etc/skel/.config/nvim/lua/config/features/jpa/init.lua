-- ═══════════════════════════════════════════════════════════
--                  JPA BUDDY++ ENTRY POINT
-- ═══════════════════════════════════════════════════════════
--
-- Comprehensive JPA tooling - Better than IntelliJ JPA Buddy!
--
-- Features:
-- - Entity → SQL DDL (PostgreSQL, MySQL, Oracle, SQL Server, H2, SQLite)
-- - Spring Data repository scaffolding
-- - DTO generation
-- - Migration files (Flyway & Liquibase)
-- - ERD generation (PlantUML & Mermaid)
-- - REST controller scaffolding
-- - Entity validation
--
-- ═══════════════════════════════════════════════════════════

local M = {}

local parser = require("lsp.java.features.jpa.parser")
local generator = require("lsp.java.features.jpa.generator")
local repository = require("lsp.java.features.jpa.repository")
local dto = require("lsp.java.features.jpa.dto")
local migration = require("lsp.java.features.jpa.migration")
local documentation = require("lsp.java.features.jpa.documentation")
local controller = require("lsp.java.features.jpa.controller")

---Generate SQL DDL from current entity
---@param dialect string|nil Database dialect (default: postgres)
function M.generate_sql(dialect)
  local entity = parser.parse_entity()

  if not entity then
    vim.notify("Current buffer is not a JPA entity", vim.log.levels.WARN)
    return
  end

  dialect = dialect or "postgres"
  local sql = generator.generate_ddl(entity, dialect)

  -- Show in split window
  M.show_generated_code(sql, "sql")
end

---Generate SQL for all entities in project
---@param dialect string|nil Database dialect
function M.generate_project_sql(dialect)
  vim.ui.select(vim.tbl_values(generator.dialects), {
    prompt = "Select database dialect:",
  }, function(selected)
    if not selected then
      return
    end

    -- Find dialect key from value
    local dialect_key
    for key, value in pairs(generator.dialects) do
      if value == selected then
        dialect_key = key
        break
      end
    end

    local sql = generator.generate_project_ddl(dialect_key)

    -- Ask where to save
    vim.ui.input({
      prompt = "Save to (default: schema.sql): ",
      default = "schema.sql",
    }, function(filename)
      if filename and filename ~= "" then
        generator.save_ddl(sql, vim.fn.getcwd() .. "/" .. filename)
        vim.cmd("edit " .. vim.fn.getcwd() .. "/" .. filename)
      else
        M.show_generated_code(sql, "sql")
      end
    end)
  end)
end

---Generate Spring Data repository
function M.generate_repository()
  local entity = parser.parse_entity()

  if not entity then
    vim.notify("Current buffer is not a JPA entity", vim.log.levels.WARN)
    return
  end

  local repo_code = repository.generate_repository(entity, "JpaRepository")
  M.show_generated_code(repo_code, "java")
end

---Generate DTO
function M.generate_dto()
  local entity = parser.parse_entity()

  if not entity then
    vim.notify("Current buffer is not a JPA entity", vim.log.levels.WARN)
    return
  end

  local dto_code = dto.generate_dto(entity)
  M.show_generated_code(dto_code, "java")
end

---Generate REST controller
function M.generate_controller()
  local entity = parser.parse_entity()

  if not entity then
    vim.notify("Current buffer is not a JPA entity", vim.log.levels.WARN)
    return
  end

  local controller_code = controller.generate_rest_controller(entity)
  M.show_generated_code(controller_code, "java")
end

---Generate migration file
---@param migration_type string "flyway" or "liquibase"
function M.generate_migration(migration_type)
  local entity = parser.parse_entity()

  if not entity then
    vim.notify("Current buffer is not a JPA entity", vim.log.levels.WARN)
    return
  end

  vim.ui.select(vim.tbl_values(generator.dialects), {
    prompt = "Select database dialect:",
  }, function(selected)
    if not selected then
      return
    end

    -- Find dialect key
    local dialect_key
    for key, value in pairs(generator.dialects) do
      if value == selected then
        dialect_key = key
        break
      end
    end

    local filename, content
    if migration_type == "flyway" then
      filename, content = migration.generate_flyway_migration(entity, dialect_key)
    else
      content = migration.generate_liquibase_changeset(entity, dialect_key)
      filename = entity.table_name .. ".xml"
    end

    migration.save_migration(filename, content, migration_type)
  end)
end

---Generate ERD
---@param format string "plantuml" or "mermaid"
function M.generate_erd(format)
  format = format or "plantuml"

  local erd_content
  if format == "plantuml" then
    erd_content = documentation.generate_plantuml_erd()
  else
    erd_content = documentation.generate_mermaid_erd()
  end

  documentation.save_erd(erd_content, format)

  -- Open in new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(erd_content, "\n"))
  vim.api.nvim_set_option_value("filetype", format == "plantuml" and "plantuml" or "mermaid", { buf = buf })

  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(buf)
end

---Show generated code in split window
---@param code string Generated code
---@param filetype string File type
function M.show_generated_code(code, filetype)
  -- Create new buffer
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, vim.split(code, "\n"))
  vim.api.nvim_set_option_value("filetype", filetype, { buf = buf })

  -- Open in split
  vim.cmd("vsplit")
  vim.api.nvim_set_current_buf(buf)

  -- Add keymap to save
  vim.keymap.set("n", "<leader>w", function()
    vim.ui.input({
      prompt = "Save as: ",
      completion = "file",
    }, function(filename)
      if filename and filename ~= "" then
        vim.cmd("write " .. filename)
      end
    end)
  end, { buffer = buf, desc = "Save generated file" })
end

---Setup JPA Buddy++ features
function M.setup()
  -- Create user commands
  vim.api.nvim_create_user_command("JPAGenerateSQL", function(args)
    M.generate_sql(args.args ~= "" and args.args or nil)
  end, {
    nargs = "?",
    complete = function()
      return vim.tbl_keys(generator.dialects)
    end,
    desc = "Generate SQL DDL from current entity",
  })

  vim.api.nvim_create_user_command("JPAGenerateProjectSQL", function()
    M.generate_project_sql()
  end, {
    desc = "Generate SQL DDL for all entities in project",
  })

  vim.api.nvim_create_user_command("JPAGenerateRepository", function()
    M.generate_repository()
  end, {
    desc = "Generate Spring Data repository for current entity",
  })

  vim.api.nvim_create_user_command("JPAGenerateDTO", function()
    M.generate_dto()
  end, {
    desc = "Generate DTO for current entity",
  })

  vim.api.nvim_create_user_command("JPAGenerateController", function()
    M.generate_controller()
  end, {
    desc = "Generate REST controller for current entity",
  })

  vim.api.nvim_create_user_command("JPAGenerateFlywayMigration", function()
    M.generate_migration("flyway")
  end, {
    desc = "Generate Flyway migration for current entity",
  })

  vim.api.nvim_create_user_command("JPAGenerateLiquibaseMigration", function()
    M.generate_migration("liquibase")
  end, {
    desc = "Generate Liquibase migration for current entity",
  })

  vim.api.nvim_create_user_command("JPAGenerateERD", function(args)
    local format = args.args ~= "" and args.args or "plantuml"
    M.generate_erd(format)
  end, {
    nargs = "?",
    complete = function()
      return { "plantuml", "mermaid" }
    end,
    desc = "Generate ERD (PlantUML or Mermaid)",
  })

  vim.notify("JPA Buddy++ loaded", vim.log.levels.DEBUG)
end

return M
