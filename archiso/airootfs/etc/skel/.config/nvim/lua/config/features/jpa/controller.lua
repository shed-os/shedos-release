-- ═══════════════════════════════════════════════════════════
--             REST CONTROLLER SCAFFOLDING
-- ═══════════════════════════════════════════════════════════

local M = {}

---Generate Spring REST controller for entity
---@param entity table Entity metadata
---@return string java_code Controller class code
function M.generate_rest_controller(entity)
  local template = [[
package %s.controller;

import %s.domain.%s;
import %s.dto.%sDTO;
import %s.repository.%sRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.stream.Collectors;

@RestController
@RequestMapping("/api/%s")
@RequiredArgsConstructor
public class %sController {

    private final %sRepository repository;

    @GetMapping
    public List<%sDTO> getAll() {
        return repository.findAll().stream()
            .map(%sDTO::fromEntity)
            .collect(Collectors.toList());
    }

    @GetMapping("/{id}")
    public ResponseEntity<%sDTO> getById(@PathVariable Long id) {
        return repository.findById(id)
            .map(%sDTO::fromEntity)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }

    @PostMapping
    public %sDTO create(@RequestBody %sDTO dto) {
        %s entity = new %s();
        // TODO: Map DTO to entity
        %s saved = repository.save(entity);
        return %sDTO.fromEntity(saved);
    }

    @PutMapping("/{id}")
    public ResponseEntity<%sDTO> update(@PathVariable Long id, @RequestBody %sDTO dto) {
        return repository.findById(id)
            .map(entity -> {
                // TODO: Update entity from DTO
                %s updated = repository.save(entity);
                return ResponseEntity.ok(%sDTO.fromEntity(updated));
            })
            .orElse(ResponseEntity.notFound().build());
    }

    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(@PathVariable Long id) {
        if (repository.existsById(id)) {
            repository.deleteById(id);
            return ResponseEntity.noContent().build();
        }
        return ResponseEntity.notFound().build();
    }
}
]]

  local resource_name = entity.class_name:lower() .. "s" -- Simple pluralization

  return string.format(
    template,
    entity.package,                    -- package declaration
    entity.package,                    -- import entity
    entity.class_name,
    entity.package,                    -- import DTO
    entity.class_name,
    entity.package,                    -- import repository
    entity.class_name,
    resource_name,                     -- @RequestMapping path
    entity.class_name,                 -- class name
    entity.class_name,                 -- repository field
    entity.class_name,                 -- getAll return type
    entity.class_name,                 -- getAll map
    entity.class_name,                 -- getById return type
    entity.class_name,                 -- getById map
    entity.class_name,                 -- create return type
    entity.class_name,                 -- create param type
    entity.class_name,                 -- create entity instantiation
    entity.class_name,
    entity.class_name,                 -- create saved entity
    entity.class_name,                 -- create return DTO
    entity.class_name,                 -- update return type
    entity.class_name,                 -- update param type
    entity.class_name,                 -- update entity
    entity.class_name                  -- update return DTO
  )
end

return M
