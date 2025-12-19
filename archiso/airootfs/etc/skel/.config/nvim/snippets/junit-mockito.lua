-- ═══════════════════════════════════════════════════════════
--            JUNIT 5 & MOCKITO SNIPPETS
-- ═══════════════════════════════════════════════════════════

local ls = require("luasnip")
local s = ls.snippet
local t = ls.text_node
local i = ls.insert_node
local f = ls.function_node
local fmt = require("luasnip.extras.fmt").fmt

return {
  -- JUnit 5 Test Class
  s("junit5", fmt([[
@ExtendWith(MockitoExtension.class)
class {}Test {{

    @InjectMocks
    private {} {};

    @Mock
    private {} {};

    {}

    @Test
    @DisplayName("{}")
    void {}() {{
        // Given
        {}

        // When
        {}

        // Then
        {}
    }}
}}
]], {
    i(1, "Service"),
    i(2, "Service"),
    i(3, "service"),
    i(4, "Repository"),
    i(5, "repository"),
    i(6, "// Additional mocks"),
    i(7, "Should do something"),
    i(8, "shouldDoSomething"),
    i(9, "// Arrange"),
    i(10, "// Act"),
    i(11, "// Assert"),
  })),

  -- @Test method (AAA pattern)
  s("jtest", fmt([[
@Test
@DisplayName("{}")
void {}() {{
    // Given
    {}

    // When
    {}

    // Then
    {}
}}
]], {
    i(1, "Should test something"),
    i(2, "shouldTestSomething"),
    i(3, "// Arrange"),
    i(4, "// Act"),
    i(5, "// Assert with assertThat"),
  })),

  -- Mockito when().thenReturn()
  s("when", fmt([[
when({}.{}({})).thenReturn({});
]], {
    i(1, "mock"),
    i(2, "method"),
    i(3, "args"),
    i(4, "returnValue"),
  })),

  -- Mockito verify()
  s("verify", fmt([[
verify({}, times({})).{}({});
]], {
    i(1, "mock"),
    i(2, "1"),
    i(3, "method"),
    i(4, "args"),
  })),

  -- ArgumentCaptor
  s("captor", fmt([[
@Captor
private ArgumentCaptor<{}> {}Captor;

// In test method:
verify({}).{}({}Captor.capture());
{} captured = {}Captor.getValue();
assertThat(captured).{}({});
]], {
    i(1, "Type"),
    i(2, "argument"),
    i(3, "mock"),
    i(4, "method"),
    i(5, "argument"),
    i(6, "Type"),
    i(7, "argument"),
    i(8, "isEqualTo"),
    i(9, "expectedValue"),
  })),

  -- @BeforeEach
  s("before", fmt([[
@BeforeEach
void setUp() {{
    {}
}}
]], {
    i(1, "// Setup code"),
  })),

  -- @AfterEach
  s("after", fmt([[
@AfterEach
void tearDown() {{
    {}
}}
]], {
    i(1, "// Cleanup code"),
  })),

  -- @ParameterizedTest
  s("paramtest", fmt([[
@ParameterizedTest
@ValueSource({} = {{ {} }})
@DisplayName("{}")
void {}({} {}) {{
    // Given
    {}

    // When
    {}

    // Then
    {}
}}
]], {
    i(1, "strings"),
    i(2, '"value1", "value2", "value3"'),
    i(3, "Should test with parameter"),
    i(4, "shouldTestWithParameter"),
    i(5, "String"),
    i(6, "param"),
    i(7, "// Arrange"),
    i(8, "// Act"),
    i(9, "// Assert"),
  })),

  -- @Nested test class
  s("nested", fmt([[
@Nested
@DisplayName("{}")
class {} {{

    @Test
    @DisplayName("{}")
    void {}() {{
        {}
    }}
}}
]], {
    i(1, "When testing specific scenario"),
    i(2, "WhenTestingScenario"),
    i(3, "Should behave as expected"),
    i(4, "shouldBehaveAsExpected"),
    i(5, "// Test implementation"),
  })),

  -- AssertJ assertions
  s("assertj", fmt([[
assertThat({})
    .isNotNull()
    .{}({});
]], {
    i(1, "actual"),
    i(2, "isEqualTo"),
    i(3, "expected"),
  })),

  -- Mock behavior with doThrow
  s("dothrow", fmt([[
doThrow(new {}("{}"))
    .when({})
    .{}({});
]], {
    i(1, "RuntimeException"),
    i(2, "Error message"),
    i(3, "mock"),
    i(4, "method"),
    i(5, "args"),
  })),

  -- Mock void method with doNothing
  s("donothing", fmt([[
doNothing().when({}).{}({});
]], {
    i(1, "mock"),
    i(2, "method"),
    i(3, "args"),
  })),

  -- @SpringBootTest for integration tests
  s("springtest", fmt([[
@SpringBootTest
@AutoConfigureMockMvc
class {}IntegrationTest {{

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private {} {};

    @Test
    @DisplayName("{}")
    void {}() throws Exception {{
        // Given
        {}

        // When & Then
        mockMvc.perform(get("/api/{}"))
            .andExpect(status().isOk())
            .andExpect(jsonPath("$.{}").value({}));
    }}
}}
]], {
    i(1, "Controller"),
    i(2, "Repository"),
    i(3, "repository"),
    i(4, "Should retrieve resource"),
    i(5, "shouldRetrieveResource"),
    i(6, "// Test data setup"),
    i(7, "resources"),
    i(8, "field"),
    i(9, "expectedValue"),
  })),
}
