-- ═══════════════════════════════════════════════════════════
--            SPRING BOOT SNIPPETS
-- ═══════════════════════════════════════════════════════════

local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- @RestController with full CRUD
  s("sbrc", fmt([[
@RestController
@RequestMapping("/api/{}")
@RequiredArgsConstructor
public class {}Controller {{

    private final {}Service service;

    @GetMapping
    public ResponseEntity<List<{}>> getAll() {{
        return ResponseEntity.ok(service.findAll());
    }}

    @GetMapping("/{{id}}")
    public ResponseEntity<{}> getById(@PathVariable Long id) {{
        return service.findById(id)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }}

    @PostMapping
    public ResponseEntity<{}> create(@RequestBody @Valid {} dto) {{
        {} created = service.save(dto);
        return ResponseEntity.status(HttpStatus.CREATED).body(created);
    }}

    @PutMapping("/{{id}}")
    public ResponseEntity<{}> update(@PathVariable Long id, @RequestBody @Valid {} dto) {{
        return service.update(id, dto)
            .map(ResponseEntity::ok)
            .orElse(ResponseEntity.notFound().build());
    }}

    @DeleteMapping("/{{id}}")
    public ResponseEntity<Void> delete(@PathVariable Long id) {{
        service.deleteById(id);
        return ResponseEntity.noContent().build();
    }}
}}
]], {
    i(1, "users"),
    i(2, "User"),
    i(3, "User"),
    i(4, "User"),
    i(5, "User"),
    i(6, "User"),
    i(7, "User"),
    i(8, "User"),
    i(9, "User"),
    i(10, "User"),
  })),

  -- @Service with repository
  s("sbserv", fmt([[
@Service
@RequiredArgsConstructor
@Slf4j
public class {}Service {{

    private final {}Repository repository;

    public List<{}> findAll() {{
        log.debug("Finding all {}s");
        return repository.findAll();
    }}

    public Optional<{}> findById(Long id) {{
        log.debug("Finding {} by id: {{}}", id);
        return repository.findById(id);
    }}

    public {} save({} entity) {{
        log.debug("Saving {}: {{}}", entity);
        return repository.save(entity);
    }}

    @Transactional
    public Optional<{}> update(Long id, {} entity) {{
        return repository.findById(id)
            .map(existing -> {{
                // TODO: Update fields
                return repository.save(existing);
            }});
    }}

    public void deleteById(Long id) {{
        log.debug("Deleting {} by id: {{}}", id);
        repository.deleteById(id);
    }}
}}
]], {
    i(1, "User"),
    i(2, "User"),
    i(3, "User"),
    i(4, "user"),
    i(5, "User"),
    i(6, "user"),
    i(7, "User"),
    i(8, "User"),
    i(9, "user"),
    i(10, "User"),
    i(11, "User"),
    i(12, "user"),
  })),

  -- @Entity with common fields
  s("sbent", fmt([[
@Entity
@Table(name = "{}")
@Data
@NoArgsConstructor
@AllArgsConstructor
public class {} {{

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String {};

    @CreatedDate
    @Column(nullable = false, updatable = false)
    private LocalDateTime createdAt;

    @LastModifiedDate
    private LocalDateTime updatedAt;

    {}
}}
]], {
    i(1, "users"),
    i(2, "User"),
    i(3, "name"),
    i(4, "// Additional fields"),
  })),

  -- @Configuration class
  s("sbconf", fmt([[
@Configuration
public class {}Config {{

    {}

    @Bean
    public {} {}() {{
        {}
        return {};
    }}
}}
]], {
    i(1, "Application"),
    i(2, "// Additional fields/dependencies"),
    i(3, "Type"),
    i(4, "beanName"),
    i(5, "// Bean configuration"),
    i(6, "new Type()"),
  })),

  -- @ConfigurationProperties
  s("sbprop", fmt([[
@ConfigurationProperties(prefix = "{}")
@Validated
@Data
public class {}Properties {{

    {}

    private String {} = "{}";

    {}
}}
]], {
    i(1, "app"),
    i(2, "Application"),
    i(3, "// Additional fields"),
    i(4, "property"),
    i(5, "default-value"),
    i(6, "// More properties"),
  })),

  -- Exception class
  s("sbex", fmt([[
public class {} extends RuntimeException {{

    public {}(String message) {{
        super(message);
    }}

    public {}(String message, Throwable cause) {{
        super(message, cause);
    }}
}}
]], {
    i(1, "ResourceNotFoundException"),
    i(2, "ResourceNotFoundException"),
    i(3, "ResourceNotFoundException"),
  })),

  -- @ControllerAdvice for global exception handling
  s("sbadvice", fmt([[
@RestControllerAdvice
@Slf4j
public class GlobalExceptionHandler {{

    @ExceptionHandler(ResourceNotFoundException.class)
    public ResponseEntity<ErrorResponse> handleResourceNotFound(ResourceNotFoundException ex) {{
        log.error("Resource not found: {{}}", ex.getMessage());
        return ResponseEntity
            .status(HttpStatus.NOT_FOUND)
            .body(new ErrorResponse(HttpStatus.NOT_FOUND.value(), ex.getMessage()));
    }}

    @ExceptionHandler(ValidationException.class)
    public ResponseEntity<ErrorResponse> handleValidation(ValidationException ex) {{
        log.error("Validation error: {{}}", ex.getMessage());
        return ResponseEntity
            .status(HttpStatus.BAD_REQUEST)
            .body(new ErrorResponse(HttpStatus.BAD_REQUEST.value(), ex.getMessage()));
    }}

    @ExceptionHandler(Exception.class)
    public ResponseEntity<ErrorResponse> handleGeneral(Exception ex) {{
        log.error("Unexpected error", ex);
        return ResponseEntity
            .status(HttpStatus.INTERNAL_SERVER_ERROR)
            .body(new ErrorResponse(HttpStatus.INTERNAL_SERVER_ERROR.value(), "An unexpected error occurred"));
    }}
}}
]], {})),

  -- Spring Data Repository
  s("sbrepo", fmt([[
@Repository
public interface {}Repository extends JpaRepository<{}, Long> {{

    Optional<{}> findBy{}(String {});

    List<{}> findBy{}(String {});

    @Query("{}")
    {}

    boolean existsBy{}(String {});
}}
]], {
    i(1, "User"),
    i(2, "User"),
    i(3, "User"),
    i(4, "Username"),
    i(5, "username"),
    i(6, "User"),
    i(7, "Status"),
    i(8, "status"),
    i(9, "SELECT u FROM User u WHERE u.active = true"),
    i(10, "List<User> findActiveUsers();"),
    i(11, "Email"),
    i(12, "email"),
  })),
}
