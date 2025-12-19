-- ═══════════════════════════════════════════════════════════
--                     DTO GENERATION
-- ═══════════════════════════════════════════════════════════

local M = {}

---Generate DTO from entity
---@param entity table Entity metadata
---@return string java_code DTO class code
function M.generate_dto(entity)
  local template = [[
package %s.dto;

import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.AllArgsConstructor;
%s

@Data
@NoArgsConstructor
@AllArgsConstructor
public class %sDTO {
%s

    public static %sDTO fromEntity(%s entity) {
        return new %sDTO(%s);
    }
}
]]

  -- Generate fields
  local dto_fields = {}
  local from_entity_params = {}

  for _, field in ipairs(entity.fields) do
    table.insert(dto_fields, string.format("    private %s %s;", field.type, field.name))
    table.insert(from_entity_params, "entity.get" .. field.name:sub(1, 1):upper() .. field.name:sub(2) .. "()")
  end

  -- Additional imports
  local imports = ""
  for _, field in ipairs(entity.fields) do
    if field.type:match("LocalDate") or field.type:match("LocalTime") or field.type:match("LocalDateTime") then
      imports = "import java.time.*;"
      break
    end
  end

  return string.format(
    template,
    entity.package,
    imports,
    entity.class_name,
    table.concat(dto_fields, "\n"),
    entity.class_name,
    entity.class_name,
    entity.class_name,
    table.concat(from_entity_params, ", ")
  )
end

return M
