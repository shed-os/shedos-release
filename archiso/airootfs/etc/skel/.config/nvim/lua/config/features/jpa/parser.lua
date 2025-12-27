-- ═══════════════════════════════════════════════════════════
--                    JPA ENTITY PARSER
-- ═══════════════════════════════════════════════════════════
--
-- Parse JPA entities using JDTLS and Treesitter
-- Extracts entity metadata, relationships, and constraints
--
-- ═══════════════════════════════════════════════════════════

local M = {}

---Check if buffer contains a JPA entity
---@param bufnr number|nil Buffer number (default: current)
---@return boolean is_entity True if buffer contains @Entity
function M.is_jpa_entity(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, 100, false)

  for _, line in ipairs(lines) do
    if line:match("@Entity") or line:match("@javax%.persistence%.Entity") or line:match("@jakarta%.persistence%.Entity") then
      return true
    end
  end

  return false
end

---Extract entity metadata from buffer
---@param bufnr number|nil Buffer number (default: current)
---@return table|nil entity Entity metadata or nil
function M.parse_entity(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if not M.is_jpa_entity(bufnr) then
    return nil
  end

  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local content = table.concat(lines, "\n")

  local entity = {
    class_name = nil,
    table_name = nil,
    schema = nil,
    catalog = nil,
    fields = {},
    relationships = {},
    indexes = {},
    constraints = {},
    package = nil,
    imports = {},
  }

  -- Extract package
  entity.package = content:match("package%s+([%w%.]+);")

  -- Extract class name
  entity.class_name = content:match("class%s+(%w+)")

  -- Extract @Table annotation
  local table_annotation = content:match("@Table%s*%((.-)%)")
  if table_annotation then
    entity.table_name = table_annotation:match('name%s*=%s*"([^"]+)"')
    entity.schema = table_annotation:match('schema%s*=%s*"([^"]+)"')
    entity.catalog = table_annotation:match('catalog%s*=%s*"([^"]+)"')
  end

  -- Default table name to class name if not specified
  if not entity.table_name then
    entity.table_name = M.camel_to_snake(entity.class_name)
  end

  -- Parse fields
  entity.fields = M.parse_fields(content)

  -- Parse relationships
  entity.relationships = M.parse_relationships(content)

  return entity
end

---Parse entity fields
---@param content string Entity source code
---@return table fields List of field metadata
function M.parse_fields(content)
  local fields = {}

  -- Match field declarations with annotations
  -- This is a simplified parser - production would use Treesitter or JDTLS
  for field_block in content:gmatch("(@%w+[^\n]-\n%s*private%s+[^\n]+;)") do
    local field = M.parse_single_field(field_block)
    if field then
      table.insert(fields, field)
    end
  end

  return fields
end

---Parse single field
---@param field_block string Field declaration with annotations
---@return table|nil field Field metadata
function M.parse_single_field(field_block)
  local field = {
    name = nil,
    type = nil,
    column_name = nil,
    nullable = true,
    unique = false,
    length = nil,
    precision = nil,
    scale = nil,
    is_id = false,
    generated_value = nil,
    enumerated = nil,
  }

  -- Extract field name and type
  local field_type, field_name = field_block:match("private%s+([%w<>,%s]+)%s+(%w+)%s*;")
  if not field_name then
    return nil
  end

  field.name = field_name
  field.type = field_type:gsub("%s+", "")

  -- Check for @Id
  if field_block:match("@Id") then
    field.is_id = true
  end

  -- Check for @GeneratedValue
  if field_block:match("@GeneratedValue") then
    local strategy = field_block:match('@GeneratedValue%s*%([^%)]*strategy%s*=%s*GenerationType%.(%w+)')
    field.generated_value = strategy or "AUTO"
  end

  -- Extract @Column annotation
  local column_annotation = field_block:match("@Column%s*%((.-)%)")
  if column_annotation then
    field.column_name = column_annotation:match('name%s*=%s*"([^"]+)"')

    local nullable_str = column_annotation:match("nullable%s*=%s*(%w+)")
    if nullable_str then
      field.nullable = nullable_str == "true"
    end

    local unique_str = column_annotation:match("unique%s*=%s*(%w+)")
    if unique_str then
      field.unique = unique_str == "true"
    end

    field.length = tonumber(column_annotation:match("length%s*=%s*(%d+)"))
    field.precision = tonumber(column_annotation:match("precision%s*=%s*(%d+)"))
    field.scale = tonumber(column_annotation:match("scale%s*=%s*(%d+)"))
  end

  -- Default column name
  if not field.column_name then
    field.column_name = M.camel_to_snake(field.name)
  end

  -- Check for @Enumerated
  if field_block:match("@Enumerated") then
    local enum_type = field_block:match("@Enumerated%s*%(%s*EnumType%.(%w+)")
    field.enumerated = enum_type or "ORDINAL"
  end

  return field
end

---Parse entity relationships
---@param content string Entity source code
---@return table relationships List of relationship metadata
function M.parse_relationships(content)
  local relationships = {}

  -- Match relationship annotations
  local relationship_patterns = {
    "@OneToOne",
    "@OneToMany",
    "@ManyToOne",
    "@ManyToMany",
  }

  for _, pattern in ipairs(relationship_patterns) do
    for rel_block in content:gmatch("(" .. pattern .. "[^\n]-\n%s*private%s+[^\n]+;)") do
      local relationship = M.parse_single_relationship(rel_block, pattern)
      if relationship then
        table.insert(relationships, relationship)
      end
    end
  end

  return relationships
end

---Parse single relationship
---@param rel_block string Relationship declaration
---@param rel_type string Relationship type (@OneToOne, etc.)
---@return table|nil relationship Relationship metadata
function M.parse_single_relationship(rel_block, rel_type)
  local relationship = {
    type = rel_type:gsub("@", ""),
    field_name = nil,
    target_entity = nil,
    mapped_by = nil,
    cascade = {},
    fetch = nil,
    optional = true,
  }

  -- Extract field name and type
  local field_type, field_name = rel_block:match("private%s+([%w<>,%s]+)%s+(%w+)%s*;")
  if not field_name then
    return nil
  end

  relationship.field_name = field_name
  relationship.target_entity = field_type:match("([%w]+)")

  -- Extract relationship properties
  local annotation = rel_block:match(rel_type .. "%s*%((.-)%)")
  if annotation then
    relationship.mapped_by = annotation:match('mappedBy%s*=%s*"([^"]+)"')
    relationship.fetch = annotation:match("fetch%s*=%s*FetchType%.(%w+)")

    local optional_str = annotation:match("optional%s*=%s*(%w+)")
    if optional_str then
      relationship.optional = optional_str == "true"
    end

    -- Parse cascade types
    local cascade_str = annotation:match("cascade%s*=%s*{([^}]+)}")
    if cascade_str then
      for cascade_type in cascade_str:gmatch("CascadeType%.(%w+)") do
        table.insert(relationship.cascade, cascade_type)
      end
    end
  end

  return relationship
end

---Convert camelCase to snake_case
---@param str string CamelCase string
---@return string snake_case Snake case string
function M.camel_to_snake(str)
  if not str then
    return ""
  end

  -- Insert underscore before uppercase letters
  local result = str:gsub("(%u)", "_%1"):lower()

  -- Remove leading underscore
  if result:sub(1, 1) == "_" then
    result = result:sub(2)
  end

  return result
end

---Convert snake_case to CamelCase
---@param str string Snake case string
---@param first_upper boolean First letter uppercase (default: true)
---@return string camelCase CamelCase string
function M.snake_to_camel(str, first_upper)
  if not str then
    return ""
  end

  first_upper = first_upper ~= false

  local result = str:gsub("_(%w)", function(c)
    return c:upper()
  end)

  if first_upper then
    result = result:sub(1, 1):upper() .. result:sub(2)
  end

  return result
end

---Get all entities in project
---@param project_root string|nil Project root (default: cwd)
---@return table entities List of entity file paths
function M.find_all_entities(project_root)
  project_root = project_root or vim.fn.getcwd()

  vim.notify("Searching for JPA entities in: " .. project_root, vim.log.levels.INFO)

  local entities = {}

  -- Use fd or find to search for Java files with @Entity
  local cmd
  if vim.fn.executable("fd") == 1 then
    -- fd is faster and handles recursion well
    cmd = string.format("cd '%s' && fd -t f -e java --exec grep -l '@Entity' 2>/dev/null", project_root)
  elseif vim.fn.executable("find") == 1 then
    -- find with recursive search through all subdirectories
    cmd = string.format("find '%s' -type f -name '*.java' -exec grep -l '@Entity' {} \\; 2>/dev/null", project_root)
  else
    vim.notify("Neither 'fd' nor 'find' command found!", vim.log.levels.ERROR)
    return {}
  end

  vim.notify("Executing: " .. cmd, vim.log.levels.DEBUG)

  local handle = io.popen(cmd)
  if not handle then
    vim.notify("Failed to execute search command", vim.log.levels.ERROR)
    return {}
  end

  for line in handle:lines() do
    if line and line ~= "" then
      -- Make path absolute if it's relative
      local filepath = line
      if not filepath:match("^/") then
        filepath = project_root .. "/" .. filepath
      end
      table.insert(entities, filepath)
    end
  end
  handle:close()

  vim.notify(string.format("Found %d JPA entities", #entities), vim.log.levels.INFO)

  return entities
end

---Parse all entities in project
---@param project_root string|nil Project root (default: cwd)
---@return table entities List of parsed entities
function M.parse_all_entities(project_root)
  local entity_files = M.find_all_entities(project_root)
  local entities = {}

  for _, file_path in ipairs(entity_files) do
    -- Read file
    local file = io.open(file_path, "r")
    if file then
      local content = file:read("*a")
      file:close()

      -- Create temporary buffer to parse
      local bufnr = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, vim.split(content, "\n"))

      local entity = M.parse_entity(bufnr)
      if entity then
        entity.file_path = file_path
        table.insert(entities, entity)
      end

      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
  end

  return entities
end

---Get Java type for SQL type
---@param sql_type string SQL type
---@return string java_type Java type
function M.sql_type_to_java(sql_type)
  local type_map = {
    VARCHAR = "String",
    TEXT = "String",
    CHAR = "String",
    INTEGER = "Integer",
    INT = "Integer",
    BIGINT = "Long",
    SMALLINT = "Short",
    TINYINT = "Byte",
    DECIMAL = "BigDecimal",
    NUMERIC = "BigDecimal",
    FLOAT = "Float",
    DOUBLE = "Double",
    REAL = "Float",
    BOOLEAN = "Boolean",
    BIT = "Boolean",
    DATE = "LocalDate",
    TIME = "LocalTime",
    TIMESTAMP = "LocalDateTime",
    DATETIME = "LocalDateTime",
    BLOB = "byte[]",
    CLOB = "String",
    UUID = "UUID",
  }

  return type_map[sql_type:upper()] or "String"
end

---Get SQL type for Java type
---@param java_type string Java type
---@return string sql_type SQL type
function M.java_type_to_sql(java_type)
  local type_map = {
    String = "VARCHAR",
    Integer = "INTEGER",
    Long = "BIGINT",
    Short = "SMALLINT",
    Byte = "TINYINT",
    BigDecimal = "DECIMAL",
    Float = "FLOAT",
    Double = "DOUBLE",
    Boolean = "BOOLEAN",
    LocalDate = "DATE",
    LocalTime = "TIME",
    LocalDateTime = "TIMESTAMP",
    Instant = "TIMESTAMP",
    Date = "TIMESTAMP",
    UUID = "UUID",
    ["byte[]"] = "BLOB",
  }

  return type_map[java_type] or "VARCHAR"
end

return M
