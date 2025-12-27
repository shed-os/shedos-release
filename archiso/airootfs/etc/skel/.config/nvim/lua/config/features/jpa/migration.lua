-- ═══════════════════════════════════════════════════════════
--                MIGRATION FILE GENERATION
-- ═══════════════════════════════════════════════════════════
--
-- Generate Flyway and Liquibase migration files
--
-- ═══════════════════════════════════════════════════════════

local M = {}
local generator = require("lsp.java.features.jpa.generator")

---Generate Flyway migration file
---@param entity table Entity metadata
---@param dialect string Database dialect
---@return string filename Migration filename
---@return string content Migration content
function M.generate_flyway_migration(entity, dialect)
  local timestamp = os.date("%Y%m%d%H%M%S")
  local filename = string.format("V%s__create_%s_table.sql", timestamp, entity.table_name:lower())

  local ddl = generator.generate_ddl(entity, dialect)

  return filename, ddl
end

---Generate Liquibase changeset
---@param entity table Entity metadata
---@param dialect string Database dialect
---@return string xml Liquibase changeset XML
function M.generate_liquibase_changeset(entity, dialect)
  local timestamp = os.date("%Y%m%d%H%M%S")

  local template = [[
<?xml version="1.0" encoding="UTF-8"?>
<databaseChangeLog
    xmlns="http://www.liquibase.org/xml/ns/dbchangelog"
    xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
    xsi:schemaLocation="http://www.liquibase.org/xml/ns/dbchangelog
    http://www.liquibase.org/xml/ns/dbchangelog/dbchangelog-4.x.xsd">

    <changeSet id="%s-create-%s" author="jpa-buddy-plus">
        <createTable tableName="%s">
%s
        </createTable>
    </changeSet>

</databaseChangeLog>
]]

  -- Generate column definitions for Liquibase
  local columns = {}
  for _, field in ipairs(entity.fields) do
    local column_xml = string.format(
      '            <column name="%s" type="%s"%s%s/>',
      field.column_name,
      generator.get_sql_type(field, dialect),
      field.is_id and ' autoIncrement="true"' or "",
      not field.nullable and not field.is_id and ' nullable="false"' or ""
    )
    table.insert(columns, column_xml)
  end

  return string.format(template, timestamp, entity.table_name, entity.table_name, table.concat(columns, "\n"))
end

---Save migration file
---@param filename string Migration filename
---@param content string Migration content
---@param migration_type string "flyway" or "liquibase"
---@return string file_path Path to saved migration
function M.save_migration(filename, content, migration_type)
  migration_type = migration_type or "flyway"

  local base_dir
  if migration_type == "flyway" then
    base_dir = vim.fn.getcwd() .. "/src/main/resources/db/migration"
  else
    base_dir = vim.fn.getcwd() .. "/src/main/resources/db/changelog"
    filename = "changeset-" .. filename:gsub("%.sql$", ".xml")
  end

  -- Create directory if it doesn't exist
  vim.fn.mkdir(base_dir, "p")

  local file_path = base_dir .. "/" .. filename
  local file = io.open(file_path, "w")

  if file then
    file:write(content)
    file:close()
    vim.notify(string.format("%s migration saved: %s", migration_type:sub(1, 1):upper() .. migration_type:sub(2), file_path), vim.log.levels.INFO)
    return file_path
  else
    vim.notify("Failed to save migration file", vim.log.levels.ERROR)
    return nil
  end
end

return M
