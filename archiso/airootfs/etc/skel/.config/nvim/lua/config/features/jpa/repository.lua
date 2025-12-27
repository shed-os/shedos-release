-- ═══════════════════════════════════════════════════════════
--              SPRING DATA REPOSITORY SCAFFOLDING
-- ═══════════════════════════════════════════════════════════

local M = {}
local parser = require("lsp.java.features.jpa.parser")

---Generate Spring Data JPA repository for entity
---@param entity table Entity metadata
---@param repository_type string Repository type (JpaRepository, CrudRepository, etc.)
---@return string java_code Repository interface code
function M.generate_repository(entity, repository_type)
  repository_type = repository_type or "JpaRepository"

  local template = [[
package %s.repository;

import %s.%s;
import org.springframework.data.jpa.repository.%s;
import org.springframework.stereotype.Repository;
import java.util.List;
import java.util.Optional;

@Repository
public interface %sRepository extends %s<%s, Long> {
%s
}
]]

  -- Generate custom query methods
  local custom_methods = M.generate_custom_methods(entity)

  return string.format(
    template,
    entity.package,
    entity.package .. ".domain",
    entity.class_name,
    repository_type,
    entity.class_name,
    repository_type,
    entity.class_name,
    custom_methods
  )
end

---Generate custom repository methods
---@param entity table Entity metadata
---@return string methods Custom method declarations
function M.generate_custom_methods(entity)
  local methods = {}

  -- Generate findBy methods for unique fields
  for _, field in ipairs(entity.fields) do
    if field.unique and not field.is_id then
      table.insert(
        methods,
        string.format("    Optional<%s> findBy%s(%s %s);", entity.class_name, parser.snake_to_camel(field.name), field.type, field.name)
      )
    end
  end

  return table.concat(methods, "\n")
end

return M
