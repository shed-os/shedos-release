-- ═══════════════════════════════════════════════════════════
--                    SQL DDL GENERATOR
-- ═══════════════════════════════════════════════════════════
--
-- Generate SQL DDL from JPA entities
-- Supports: PostgreSQL, MySQL, Oracle, SQL Server, H2, SQLite
--
-- ═══════════════════════════════════════════════════════════

local M = {}
local parser = require("lsp.java.features.jpa.parser")

-- Database dialects
M.dialects = {
  postgres = "PostgreSQL",
  mysql = "MySQL",
  oracle = "Oracle",
  sqlserver = "SQL Server",
  h2 = "H2",
  sqlite = "SQLite",
}

---Generate SQL DDL for entity with relationships
---@param entity table Entity metadata from parser
---@param dialect string Database dialect
---@param include_related boolean|nil Include related entity tables (default: true)
---@return string sql Generated SQL DDL
function M.generate_ddl(entity, dialect, include_related)
  dialect = dialect or "postgres"
  include_related = include_related ~= false

  local sql = {}
  local related_tables = {}

  -- Track related entities to generate their tables too
  if include_related then
    for _, rel in ipairs(entity.relationships or {}) do
      if rel.target_entity and not related_tables[rel.target_entity] then
        related_tables[rel.target_entity] = true

        -- Add comment for related table
        table.insert(sql, string.format("-- Related entity: %s (referenced by %s.%s)",
          rel.target_entity, entity.class_name, rel.field_name))
        table.insert(sql, M.generate_placeholder_table(rel.target_entity, dialect))
      end
    end

    if #sql > 0 then
      table.insert(sql, "")
    end
  end

  -- Generate main CREATE TABLE statement
  table.insert(sql, string.format("-- Entity: %s", entity.class_name))
  table.insert(sql, M.generate_create_table(entity, dialect))

  -- Generate indexes
  for _, index in ipairs(entity.indexes or {}) do
    table.insert(sql, M.generate_index(entity, index, dialect))
  end

  -- Generate foreign keys (from relationships)
  for _, rel in ipairs(entity.relationships or {}) do
    if rel.type == "ManyToOne" or (rel.type == "OneToOne" and not rel.mapped_by) then
      table.insert(sql, M.generate_foreign_key(entity, rel, dialect))
    elseif rel.type == "ManyToMany" and not rel.mapped_by then
      -- Generate join table for ManyToMany relationships
      table.insert(sql, M.generate_join_table(entity, rel, dialect))
    end
  end

  return table.concat(sql, "\n\n")
end

---Generate placeholder table for referenced entity
---@param entity_name string Entity class name
---@param dialect string Database dialect
---@return string sql CREATE TABLE statement
function M.generate_placeholder_table(entity_name, dialect)
  local table_name = parser.camel_to_snake(entity_name)

  local sql = string.format("CREATE TABLE IF NOT EXISTS %s (", M.quote_identifier(table_name, dialect))
  sql = sql .. "\n  " .. M.quote_identifier("id", dialect) .. " BIGINT PRIMARY KEY"
  sql = sql .. "\n  -- Additional columns should be defined in the actual " .. entity_name .. " entity"
  sql = sql .. "\n);"

  return sql
end

---Generate join table for ManyToMany relationship
---@param entity table Entity metadata
---@param relationship table Relationship metadata
---@param dialect string Database dialect
---@return string sql JOIN TABLE DDL
function M.generate_join_table(entity, relationship, dialect)
  local entity_table = entity.table_name
  local target_table = parser.camel_to_snake(relationship.target_entity)

  -- Convention: alphabetically ordered table names
  local table1, table2 = entity_table, target_table
  if entity_table > target_table then
    table1, table2 = target_table, entity_table
  end

  local join_table_name = table1 .. "_" .. table2

  local lines = {}
  table.insert(lines, string.format("-- Join table for %s <-> %s", entity.class_name, relationship.target_entity))
  table.insert(lines, string.format("CREATE TABLE %s (", M.quote_identifier(join_table_name, dialect)))

  local columns = {
    string.format("  %s BIGINT NOT NULL", M.quote_identifier(entity_table .. "_id", dialect)),
    string.format("  %s BIGINT NOT NULL", M.quote_identifier(target_table .. "_id", dialect)),
    string.format("  PRIMARY KEY (%s, %s)",
      M.quote_identifier(entity_table .. "_id", dialect),
      M.quote_identifier(target_table .. "_id", dialect))
  }

  table.insert(lines, table.concat(columns, ",\n"))
  table.insert(lines, ");")

  -- Add foreign key constraints
  table.insert(lines, "")
  table.insert(lines, string.format("ALTER TABLE %s ADD CONSTRAINT fk_%s_%s",
    M.quote_identifier(join_table_name, dialect),
    join_table_name,
    entity_table))
  table.insert(lines, string.format("  FOREIGN KEY (%s) REFERENCES %s(id);",
    M.quote_identifier(entity_table .. "_id", dialect),
    M.quote_identifier(entity_table, dialect)))

  table.insert(lines, "")
  table.insert(lines, string.format("ALTER TABLE %s ADD CONSTRAINT fk_%s_%s",
    M.quote_identifier(join_table_name, dialect),
    join_table_name,
    target_table))
  table.insert(lines, string.format("  FOREIGN KEY (%s) REFERENCES %s(id);",
    M.quote_identifier(target_table .. "_id", dialect),
    M.quote_identifier(target_table, dialect)))

  return table.concat(lines, "\n")
end

---Generate CREATE TABLE statement
---@param entity table Entity metadata
---@param dialect string Database dialect
---@return string sql CREATE TABLE SQL
function M.generate_create_table(entity, dialect)
  local lines = {}

  -- Table name with schema
  local full_table_name = entity.table_name
  if entity.schema then
    full_table_name = entity.schema .. "." .. full_table_name
  end

  table.insert(lines, string.format("CREATE TABLE %s (", M.quote_identifier(full_table_name, dialect)))

  -- Generate column definitions
  local column_defs = {}
  for _, field in ipairs(entity.fields) do
    table.insert(column_defs, "  " .. M.generate_column_definition(field, dialect))
  end

  -- Add relationship columns (foreign keys)
  for _, rel in ipairs(entity.relationships or {}) do
    if rel.type == "ManyToOne" or (rel.type == "OneToOne" and not rel.mapped_by) then
      local fk_column = M.generate_fk_column(rel, dialect)
      if fk_column then
        table.insert(column_defs, "  " .. fk_column)
      end
    end
  end

  -- Add primary key constraint
  local pk_fields = vim.tbl_filter(function(f)
    return f.is_id
  end, entity.fields)

  if #pk_fields > 0 then
    local pk_columns = vim.tbl_map(function(f)
      return M.quote_identifier(f.column_name, dialect)
    end, pk_fields)
    table.insert(column_defs, string.format("  PRIMARY KEY (%s)", table.concat(pk_columns, ", ")))
  end

  table.insert(lines, table.concat(column_defs, ",\n"))
  table.insert(lines, ");")

  return table.concat(lines, "\n")
end

---Generate column definition
---@param field table Field metadata
---@param dialect string Database dialect
---@return string column_def Column definition SQL
function M.generate_column_definition(field, dialect)
  local parts = {}

  -- Column name
  table.insert(parts, M.quote_identifier(field.column_name, dialect))

  -- Data type
  table.insert(parts, M.get_sql_type(field, dialect))

  -- NULL/NOT NULL
  if not field.nullable and not field.is_id then
    table.insert(parts, "NOT NULL")
  end

  -- UNIQUE constraint
  if field.unique then
    table.insert(parts, "UNIQUE")
  end

  -- AUTO_INCREMENT / SERIAL (for IDs)
  if field.is_id and field.generated_value then
    if dialect == "postgres" then
      -- PostgreSQL uses SERIAL or IDENTITY
      if field.generated_value == "IDENTITY" then
        table.insert(parts, "GENERATED ALWAYS AS IDENTITY")
      end
      -- For SERIAL, already handled in get_sql_type
    elseif dialect == "mysql" then
      table.insert(parts, "AUTO_INCREMENT")
    elseif dialect == "sqlserver" then
      table.insert(parts, "IDENTITY(1,1)")
    end
  end

  return table.concat(parts, " ")
end

---Get SQL type for field
---@param field table Field metadata
---@param dialect string Database dialect
---@return string sql_type SQL data type
function M.get_sql_type(field, dialect)
  local java_type = field.type

  -- Handle special cases first
  if field.is_id and field.generated_value then
    if dialect == "postgres" then
      if java_type == "Long" or java_type == "long" then
        return "BIGSERIAL"
      else
        return "SERIAL"
      end
    elseif dialect == "mysql" then
      if java_type == "Long" or java_type == "long" then
        return "BIGINT"
      else
        return "INT"
      end
    end
  end

  -- Standard type mappings
  local type_map = M.get_type_map(dialect)
  local sql_type = type_map[java_type] or type_map["String"]

  -- Apply length/precision/scale
  if field.length and (sql_type:match("VARCHAR") or sql_type:match("CHAR")) then
    sql_type = sql_type .. "(" .. field.length .. ")"
  elseif field.precision and sql_type:match("DECIMAL") then
    if field.scale then
      sql_type = sql_type .. "(" .. field.precision .. "," .. field.scale .. ")"
    else
      sql_type = sql_type .. "(" .. field.precision .. ")"
    end
  end

  return sql_type
end

---Get type mapping for dialect
---@param dialect string Database dialect
---@return table type_map Java type to SQL type mapping
function M.get_type_map(dialect)
  if dialect == "postgres" then
    return {
      String = "VARCHAR(255)",
      Integer = "INTEGER",
      ["int"] = "INTEGER",
      Long = "BIGINT",
      ["long"] = "BIGINT",
      Short = "SMALLINT",
      ["short"] = "SMALLINT",
      Byte = "SMALLINT",
      ["byte"] = "SMALLINT",
      BigDecimal = "DECIMAL(19,2)",
      Float = "REAL",
      ["float"] = "REAL",
      Double = "DOUBLE PRECISION",
      ["double"] = "DOUBLE PRECISION",
      Boolean = "BOOLEAN",
      ["boolean"] = "BOOLEAN",
      LocalDate = "DATE",
      LocalTime = "TIME",
      LocalDateTime = "TIMESTAMP",
      Instant = "TIMESTAMP",
      Date = "TIMESTAMP",
      UUID = "UUID",
      ["byte[]"] = "BYTEA",
    }
  elseif dialect == "mysql" then
    return {
      String = "VARCHAR(255)",
      Integer = "INT",
      ["int"] = "INT",
      Long = "BIGINT",
      ["long"] = "BIGINT",
      Short = "SMALLINT",
      ["short"] = "SMALLINT",
      Byte = "TINYINT",
      ["byte"] = "TINYINT",
      BigDecimal = "DECIMAL(19,2)",
      Float = "FLOAT",
      ["float"] = "FLOAT",
      Double = "DOUBLE",
      ["double"] = "DOUBLE",
      Boolean = "BOOLEAN",
      ["boolean"] = "BOOLEAN",
      LocalDate = "DATE",
      LocalTime = "TIME",
      LocalDateTime = "DATETIME",
      Instant = "DATETIME",
      Date = "DATETIME",
      UUID = "VARCHAR(36)",
      ["byte[]"] = "BLOB",
    }
  elseif dialect == "oracle" then
    return {
      String = "VARCHAR2(255)",
      Integer = "NUMBER(10)",
      ["int"] = "NUMBER(10)",
      Long = "NUMBER(19)",
      ["long"] = "NUMBER(19)",
      Short = "NUMBER(5)",
      ["short"] = "NUMBER(5)",
      Byte = "NUMBER(3)",
      ["byte"] = "NUMBER(3)",
      BigDecimal = "NUMBER(19,2)",
      Float = "FLOAT",
      ["float"] = "FLOAT",
      Double = "DOUBLE PRECISION",
      ["double"] = "DOUBLE PRECISION",
      Boolean = "NUMBER(1)",
      ["boolean"] = "NUMBER(1)",
      LocalDate = "DATE",
      LocalTime = "TIMESTAMP",
      LocalDateTime = "TIMESTAMP",
      Instant = "TIMESTAMP",
      Date = "TIMESTAMP",
      UUID = "VARCHAR2(36)",
      ["byte[]"] = "BLOB",
    }
  elseif dialect == "sqlserver" then
    return {
      String = "VARCHAR(255)",
      Integer = "INT",
      ["int"] = "INT",
      Long = "BIGINT",
      ["long"] = "BIGINT",
      Short = "SMALLINT",
      ["short"] = "SMALLINT",
      Byte = "TINYINT",
      ["byte"] = "TINYINT",
      BigDecimal = "DECIMAL(19,2)",
      Float = "REAL",
      ["float"] = "REAL",
      Double = "FLOAT",
      ["double"] = "FLOAT",
      Boolean = "BIT",
      ["boolean"] = "BIT",
      LocalDate = "DATE",
      LocalTime = "TIME",
      LocalDateTime = "DATETIME2",
      Instant = "DATETIME2",
      Date = "DATETIME2",
      UUID = "UNIQUEIDENTIFIER",
      ["byte[]"] = "VARBINARY(MAX)",
    }
  elseif dialect == "h2" then
    return {
      String = "VARCHAR(255)",
      Integer = "INTEGER",
      ["int"] = "INTEGER",
      Long = "BIGINT",
      ["long"] = "BIGINT",
      Short = "SMALLINT",
      ["short"] = "SMALLINT",
      Byte = "TINYINT",
      ["byte"] = "TINYINT",
      BigDecimal = "DECIMAL(19,2)",
      Float = "REAL",
      ["float"] = "REAL",
      Double = "DOUBLE",
      ["double"] = "DOUBLE",
      Boolean = "BOOLEAN",
      ["boolean"] = "BOOLEAN",
      LocalDate = "DATE",
      LocalTime = "TIME",
      LocalDateTime = "TIMESTAMP",
      Instant = "TIMESTAMP",
      Date = "TIMESTAMP",
      UUID = "UUID",
      ["byte[]"] = "BINARY",
    }
  else -- sqlite
    return {
      String = "TEXT",
      Integer = "INTEGER",
      ["int"] = "INTEGER",
      Long = "INTEGER",
      ["long"] = "INTEGER",
      Short = "INTEGER",
      ["short"] = "INTEGER",
      Byte = "INTEGER",
      ["byte"] = "INTEGER",
      BigDecimal = "REAL",
      Float = "REAL",
      ["float"] = "REAL",
      Double = "REAL",
      ["double"] = "REAL",
      Boolean = "INTEGER",
      ["boolean"] = "INTEGER",
      LocalDate = "TEXT",
      LocalTime = "TEXT",
      LocalDateTime = "TEXT",
      Instant = "TEXT",
      Date = "TEXT",
      UUID = "TEXT",
      ["byte[]"] = "BLOB",
    }
  end
end

---Generate foreign key column
---@param relationship table Relationship metadata
---@param dialect string Database dialect
---@return string|nil column_def Foreign key column definition
function M.generate_fk_column(relationship, dialect)
  -- Foreign key column name (e.g., user_id for user field)
  local fk_column_name = parser.camel_to_snake(relationship.field_name) .. "_id"

  -- Determine FK type based on target entity (usually Long/BIGINT)
  local fk_type = "BIGINT"
  if dialect == "mysql" then
    fk_type = "BIGINT"
  elseif dialect == "postgres" then
    fk_type = "BIGINT"
  elseif dialect == "oracle" then
    fk_type = "NUMBER(19)"
  elseif dialect == "sqlserver" then
    fk_type = "BIGINT"
  elseif dialect == "sqlite" then
    fk_type = "INTEGER"
  end

  local parts = {
    M.quote_identifier(fk_column_name, dialect),
    fk_type,
  }

  -- Add NOT NULL if relationship is not optional
  if not relationship.optional then
    table.insert(parts, "NOT NULL")
  end

  return table.concat(parts, " ")
end

---Generate foreign key constraint
---@param entity table Entity metadata
---@param relationship table Relationship metadata
---@param dialect string Database dialect
---@return string sql Foreign key constraint SQL
function M.generate_foreign_key(entity, relationship, dialect)
  local fk_column_name = parser.camel_to_snake(relationship.field_name) .. "_id"
  local target_table = parser.camel_to_snake(relationship.target_entity)

  local sql = string.format(
    "ALTER TABLE %s ADD CONSTRAINT fk_%s_%s FOREIGN KEY (%s) REFERENCES %s(id)",
    M.quote_identifier(entity.table_name, dialect),
    entity.table_name,
    fk_column_name,
    M.quote_identifier(fk_column_name, dialect),
    M.quote_identifier(target_table, dialect)
  )

  -- Add cascade options
  if vim.tbl_contains(relationship.cascade, "REMOVE") or vim.tbl_contains(relationship.cascade, "ALL") then
    sql = sql .. " ON DELETE CASCADE"
  end

  return sql .. ";"
end

---Generate index
---@param entity table Entity metadata
---@param index table Index metadata
---@param dialect string Database dialect
---@return string sql Index creation SQL
function M.generate_index(entity, index, dialect)
  local columns = table.concat(
    vim.tbl_map(function(col)
      return M.quote_identifier(col, dialect)
    end, index.columns),
    ", "
  )

  return string.format(
    "CREATE INDEX idx_%s_%s ON %s(%s);",
    entity.table_name,
    table.concat(index.columns, "_"),
    M.quote_identifier(entity.table_name, dialect),
    columns
  )
end

---Quote identifier based on dialect
---@param identifier string Identifier to quote
---@param dialect string Database dialect
---@return string quoted_identifier Quoted identifier
function M.quote_identifier(identifier, dialect)
  if dialect == "mysql" then
    return "`" .. identifier .. "`"
  elseif dialect == "sqlserver" then
    return "[" .. identifier .. "]"
  else -- postgres, oracle, h2, sqlite
    return '"' .. identifier .. '"'
  end
end

---Generate DDL for all entities in project
---@param dialect string Database dialect
---@return string sql Complete DDL script
function M.generate_project_ddl(dialect)
  local entities = parser.parse_all_entities()

  if #entities == 0 then
    return "-- No JPA entities found in project\n-- Check that:\n--   1. You're in a Java project directory\n--   2. Entity files have @Entity annotation\n--   3. Files are accessible (not in excluded paths)"
  end

  vim.notify(string.format("Generating DDL for %d entities...", #entities), vim.log.levels.INFO)

  -- Sort entities to handle dependencies (entities with no relationships first)
  local sorted_entities = M.sort_entities_by_dependencies(entities)

  local sql_parts = {
    "-- ═══════════════════════════════════════════════════════════",
    "-- Generated DDL for " .. (M.dialects[dialect] or dialect),
    "-- Date: " .. os.date("%Y-%m-%d %H:%M:%S"),
    "-- Total Entities: " .. #entities,
    "-- ═══════════════════════════════════════════════════════════",
    "",
    "-- Note: This script creates all tables first, then adds foreign keys",
    "-- This prevents issues with entity ordering and circular dependencies",
    "",
  }

  -- Phase 1: Generate all CREATE TABLE statements (without foreign keys)
  table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")
  table.insert(sql_parts, "-- PHASE 1: CREATE TABLES")
  table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")
  table.insert(sql_parts, "")

  local foreign_keys = {}
  local join_tables = {}

  for _, entity in ipairs(sorted_entities) do
    table.insert(sql_parts, string.format("-- Entity: %s (Table: %s)", entity.class_name, entity.table_name))
    table.insert(sql_parts, M.generate_create_table(entity, dialect))
    table.insert(sql_parts, "")

    -- Collect foreign keys for later
    for _, rel in ipairs(entity.relationships or {}) do
      if rel.type == "ManyToOne" or (rel.type == "OneToOne" and not rel.mapped_by) then
        table.insert(foreign_keys, { entity = entity, relationship = rel })
      elseif rel.type == "ManyToMany" and not rel.mapped_by then
        -- Collect join tables
        local key = entity.table_name < parser.camel_to_snake(rel.target_entity)
          and entity.table_name .. "_" .. parser.camel_to_snake(rel.target_entity)
          or parser.camel_to_snake(rel.target_entity) .. "_" .. entity.table_name

        if not join_tables[key] then
          join_tables[key] = { entity = entity, relationship = rel }
        end
      end
    end
  end

  -- Phase 2: Generate join tables for ManyToMany relationships
  if next(join_tables) then
    table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")
    table.insert(sql_parts, "-- PHASE 2: JOIN TABLES (ManyToMany relationships)")
    table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")
    table.insert(sql_parts, "")

    for _, data in pairs(join_tables) do
      table.insert(sql_parts, M.generate_join_table(data.entity, data.relationship, dialect))
      table.insert(sql_parts, "")
    end
  end

  -- Phase 3: Add foreign key constraints
  if #foreign_keys > 0 then
    table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")
    table.insert(sql_parts, "-- PHASE 3: FOREIGN KEY CONSTRAINTS")
    table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")
    table.insert(sql_parts, "")

    for _, fk_data in ipairs(foreign_keys) do
      local fk_sql = M.generate_foreign_key(fk_data.entity, fk_data.relationship, dialect)
      if fk_sql and fk_sql ~= "" then
        table.insert(sql_parts, fk_sql)
      end
    end
    table.insert(sql_parts, "")
  end

  table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")
  table.insert(sql_parts, "-- DDL Generation Complete!")
  table.insert(sql_parts, "-- ═══════════════════════════════════════════════════════════")

  return table.concat(sql_parts, "\n")
end

---Sort entities by dependencies (entities with fewer relationships first)
---@param entities table List of entities
---@return table sorted_entities Sorted list
function M.sort_entities_by_dependencies(entities)
  -- Simple sort: entities with no relationships first, then by relationship count
  local sorted = vim.deepcopy(entities)

  table.sort(sorted, function(a, b)
    local a_rel_count = #(a.relationships or {})
    local b_rel_count = #(b.relationships or {})

    if a_rel_count == b_rel_count then
      return (a.class_name or "") < (b.class_name or "")
    end

    return a_rel_count < b_rel_count
  end)

  return sorted
end

---Save DDL to file
---@param sql string SQL DDL
---@param output_path string|nil Output file path
---@return string file_path Path to saved file
function M.save_ddl(sql, output_path)
  output_path = output_path or vim.fn.getcwd() .. "/schema.sql"

  local file = io.open(output_path, "w")
  if file then
    file:write(sql)
    file:close()
    vim.notify("DDL saved to: " .. output_path, vim.log.levels.INFO)
    return output_path
  else
    vim.notify("Failed to save DDL to: " .. output_path, vim.log.levels.ERROR)
    return nil
  end
end

return M
