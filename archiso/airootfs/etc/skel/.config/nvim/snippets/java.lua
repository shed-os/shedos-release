-- Custom Java Snippets
-- Backend Engineer focused snippets

local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- Spring Boot Controller
  s("controller", fmt([[
@RestController
@RequestMapping("/api/{}")
public class {}Controller {{

    @GetMapping
    public ResponseEntity<List<{}>> getAll() {{
        {}
        return ResponseEntity.ok({});
    }}

    @GetMapping("/{{id}}")
    public ResponseEntity<{}> getById(@PathVariable Long id) {{
        {}
        return ResponseEntity.ok({});
    }}

    @PostMapping
    public ResponseEntity<{}> create(@RequestBody {} {}) {{
        {}
        return ResponseEntity.status(HttpStatus.CREATED).body({});
    }}

    @PutMapping("/{{id}}")
    public ResponseEntity<{}> update(@PathVariable Long id, @RequestBody {} {}) {{
        {}
        return ResponseEntity.ok({});
    }}

    @DeleteMapping("/{{id}}")
    public ResponseEntity<Void> delete(@PathVariable Long id) {{
        {}
        return ResponseEntity.noContent().build();
    }}
}}
]], {
    i(1, "resource"),
    f(function(args) return args[1][1]:gsub("^%l", string.upper) end, {1}),
    i(2, "Resource"),
    i(3, "// TODO: implement"),
    i(4, "list"),
    i(5, "Resource"),
    i(6, "// TODO: implement"),
    i(7, "entity"),
    i(8, "Resource"),
    i(9, "Resource"),
    i(10, "entity"),
    i(11, "// TODO: implement"),
    i(12, "created"),
    i(13, "Resource"),
    i(14, "Resource"),
    i(15, "entity"),
    i(16, "// TODO: implement"),
    i(17, "updated"),
    i(18, "// TODO: implement"),
  })),

  -- Spring Service
  s("service", fmt([[
@Service
public class {}Service {{

    private final {}Repository repository;

    public {}Service({}Repository repository) {{
        this.repository = repository;
    }}

    public List<{}> findAll() {{
        return repository.findAll();
    }}

    public Optional<{}> findById(Long id) {{
        return repository.findById(id);
    }}

    public {} save({} entity) {{
        return repository.save(entity);
    }}

    public void deleteById(Long id) {{
        repository.deleteById(id);
    }}
}}
]], {
    i(1, "Resource"),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
  })),

  -- Logger
  s("log", fmt([[
private static final Logger log = LoggerFactory.getLogger({}.class);
]], {
    f(function()
      return vim.fn.expand("%:t:r")
    end),
  })),

  -- Exception Handler
  s("exhandler", fmt([[
@ExceptionHandler({}.class)
public ResponseEntity<ErrorResponse> handle{}({}  ex) {{
    log.error("{} occurred: {{}}", ex.getMessage(), ex);
    ErrorResponse error = new ErrorResponse(
        HttpStatus.{}.value(),
        ex.getMessage(),
        LocalDateTime.now()
    );
    return ResponseEntity.status(HttpStatus.{}).body(error);
}}
]], {
    i(1, "Exception"),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
    f(function(args) return args[1][1] end, {1}),
    i(2, "BAD_REQUEST"),
    f(function(args) return args[1][1] end, {2}),
  })),

  -- JUnit Test
  s("test", fmt([[
@Test
void {}() {{
    // Given
    {}

    // When
    {}

    // Then
    {}
}}
]], {
    i(1, "testName"),
    i(2, "// arrange"),
    i(3, "// act"),
    i(4, "// assert"),
  })),
}
