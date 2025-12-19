-- ═══════════════════════════════════════════════════════════
--               ENTITY RELATIONSHIP DIAGRAM GENERATION
-- ═══════════════════════════════════════════════════════════
--
-- Generate ERDs in PlantUML and Mermaid formats
--
-- ═══════════════════════════════════════════════════════════

local M = {}
local parser = require("lsp.java.features.jpa.parser")

---Generate PlantUML ERD for project entities
---@param entities table|nil List of entities (nil = parse all)
---@return string plantuml PlantUML diagram code
function M.generate_plantuml_erd(entities)
  entities = entities or parser.parse_all_entities()

  local lines = {
    "@startuml",
    "!define Table(name,desc) class name as \"desc\" << (T,#FFAAAA) >>",
    "!define primary_key(x) <b>x</b>",
    "!define foreign_key(x) <i>x</i>",
    "hide methods",
    "hide stereotypes",
    "",
  }

  -- Generate entity definitions
  for _, entity in ipairs(entities) do
    table.insert(lines, string.format('entity "%s" {', entity.class_name))

    -- Add fields
    for _, field in ipairs(entity.fields) do
      local field_marker = field.is_id and "* " or ""
      local field_def = string.format(
        "  %s%s : %s%s",
        field_marker,
        field.column_name,
        field.type,
        not field.nullable and " NOT NULL" or ""
      )
      table.insert(lines, field_def)
    end

    table.insert(lines, "}")
    table.insert(lines, "")
  end

  -- Generate relationships
  for _, entity in ipairs(entities) do
    for _, rel in ipairs(entity.relationships or {}) do
      local rel_symbol = M.get_plantuml_relationship_symbol(rel.type)
      if rel_symbol then
        table.insert(lines, string.format('"%s" %s "%s"', entity.class_name, rel_symbol, rel.target_entity))
      end
    end
  end

  table.insert(lines, "")
  table.insert(lines, "@enduml")

  return table.concat(lines, "\n")
end

---Generate Mermaid ERD for project entities
---@param entities table|nil List of entities (nil = parse all)
---@return string mermaid Mermaid diagram code
function M.generate_mermaid_erd(entities)
  entities = entities or parser.parse_all_entities()

  local lines = {
    "erDiagram",
    "",
  }

  -- Generate entity definitions
  for _, entity in ipairs(entities) do
    table.insert(lines, string.format("    %s {", entity.class_name))

    -- Add fields
    for _, field in ipairs(entity.fields) do
      local field_def = string.format(
        "        %s %s %s",
        M.get_mermaid_type(field.type),
        field.column_name,
        field.is_id and "PK" or ""
      )
      table.insert(lines, field_def)
    end

    table.insert(lines, "    }")
    table.insert(lines, "")
  end

  -- Generate relationships
  for _, entity in ipairs(entities) do
    for _, rel in ipairs(entity.relationships or {}) do
      local rel_symbol = M.get_mermaid_relationship_symbol(rel.type)
      if rel_symbol then
        table.insert(
          lines,
          string.format("    %s %s %s : %s", entity.class_name, rel_symbol, rel.target_entity, rel.field_name)
        )
      end
    end
  end

  return table.concat(lines, "\n")
end

---Get PlantUML relationship symbol
---@param rel_type string Relationship type
---@return string|nil symbol PlantUML relationship symbol
function M.get_plantuml_relationship_symbol(rel_type)
  local symbols = {
    OneToOne = "||-||",
    OneToMany = "||--o{",
    ManyToOne = "}o--||",
    ManyToMany = "}o--o{",
  }
  return symbols[rel_type]
end

---Get Mermaid relationship symbol
---@param rel_type string Relationship type
---@return string|nil symbol Mermaid relationship symbol
function M.get_mermaid_relationship_symbol(rel_type)
  local symbols = {
    OneToOne = "||--||",
    OneToMany = "||--o{",
    ManyToOne = "}o--||",
    ManyToMany = "}o--o{",
  }
  return symbols[rel_type]
end

---Get Mermaid data type
---@param java_type string Java type
---@return string mermaid_type Mermaid type
function M.get_mermaid_type(java_type)
  local type_map = {
    String = "string",
    Integer = "int",
    Long = "long",
    Double = "double",
    Float = "float",
    Boolean = "boolean",
    LocalDate = "date",
    LocalDateTime = "datetime",
    BigDecimal = "decimal",
    UUID = "uuid",
  }
  return type_map[java_type] or "string"
end

---Save ERD to file
---@param content string ERD content
---@param format string "plantuml" or "mermaid"
---@return string file_path Path to saved file
function M.save_erd(content, format)
  format = format or "plantuml"

  local extension = format == "plantuml" and ".puml" or ".mmd"
  local file_path = vim.fn.getcwd() .. "/docs/erd" .. extension

  -- Create docs directory
  vim.fn.mkdir(vim.fn.getcwd() .. "/docs", "p")

  local file = io.open(file_path, "w")
  if file then
    file:write(content)
    file:close()
    vim.notify(string.format("ERD saved: %s", file_path), vim.log.levels.INFO)
    return file_path
  else
    vim.notify("Failed to save ERD", vim.log.levels.ERROR)
    return nil
  end
end

return M
