-- ═══════════════════════════════════════════════════════════
--                    SPRING FRAMEWORK SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- Comprehensive Spring Framework support including:
-- - Spring dependency injection
-- - Spring MVC
-- - Spring annotations (@Autowired, @Component, @Service, etc.)
-- - Bean configuration
-- - ApplicationContext support
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Common Spring annotations
M.annotations = {
    -- Core
    "@Component",
    "@Service",
    "@Repository",
    "@Controller",
    "@RestController",
    "@Configuration",
    "@Bean",
    
    -- Dependency Injection
    "@Autowired",
    "@Qualifier",
    "@Primary",
    "@Lazy",
    "@Value",
    "@Inject",
    
    -- Scope
    "@Scope",
    "@RequestScope",
    "@SessionScope",
    "@ApplicationScope",
    
    -- Web MVC
    "@RequestMapping",
    "@GetMapping",
    "@PostMapping",
    "@PutMapping",
    "@DeleteMapping",
    "@PatchMapping",
    "@PathVariable",
    "@RequestParam",
    "@RequestBody",
    "@ResponseBody",
    "@RequestHeader",
    "@ResponseStatus",
    
    -- AOP
    "@Aspect",
    "@Before",
    "@After",
    "@Around",
    "@AfterReturning",
    "@AfterThrowing",
    "@Pointcut",
    
    -- Transaction
    "@Transactional",
    "@EnableTransactionManagement",
    
    -- Async
    "@Async",
    "@EnableAsync",
    
    -- Scheduling
    "@Scheduled",
    "@EnableScheduling",
    
    -- Caching
    "@Cacheable",
    "@CachePut",
    "@CacheEvict",
    "@EnableCaching",
    
    -- Events
    "@EventListener",
    "@TransactionalEventListener",
    
    -- Validation
    "@Valid",
    "@Validated",
}

-- Check if current project uses Spring
function M.is_spring_project()
    local root_dir = vim.fn.getcwd()
    
    -- Check pom.xml
    if vim.fn.filereadable(root_dir .. "/pom.xml") == 1 then
        local pom_content = vim.fn.readfile(root_dir .. "/pom.xml")
        for _, line in ipairs(pom_content) do
            if line:match("spring%-core") or line:match("spring%-context") then
                return true
            end
        end
    end
    
    -- Check build.gradle
    if vim.fn.filereadable(root_dir .. "/build.gradle") == 1 or 
       vim.fn.filereadable(root_dir .. "/build.gradle.kts") == 1 then
        local gradle_file = vim.fn.filereadable(root_dir .. "/build.gradle") == 1 
            and root_dir .. "/build.gradle" 
            or root_dir .. "/build.gradle.kts"
        local gradle_content = vim.fn.readfile(gradle_file)
        for _, line in ipairs(gradle_content) do
            if line:match("org%.springframework") then
                return true
            end
        end
    end
    
    return false
end

-- Get Spring version
function M.get_spring_version()
    local root_dir = vim.fn.getcwd()
    
    if vim.fn.filereadable(root_dir .. "/pom.xml") == 1 then
        local pom_content = vim.fn.readfile(root_dir .. "/pom.xml")
        for _, line in ipairs(pom_content) do
            local version = line:match("<spring%.version>(.-)</spring%.version>")
            if version then
                return version
            end
        end
    end
    
    return "unknown"
end

-- Setup Spring support
function M.setup()
    if not M.is_spring_project() then
        return
    end
    
    vim.notify("Spring Framework detected", vim.log.levels.INFO)
    
    -- Add Spring-specific commands
    vim.api.nvim_create_user_command("SpringInfo", function()
        local version = M.get_spring_version()
        vim.notify(string.format("Spring Framework Version: %s", version), vim.log.levels.INFO)
    end, { desc = "Show Spring Framework information" })
    
    -- Command to find Spring beans
    vim.api.nvim_create_user_command("SpringFindBeans", function()
        -- Try fzf-lua first (LazyVim 14.x+), fallback to telescope
        local has_fzf, fzf = pcall(require, "fzf-lua")
        if has_fzf then
            fzf.live_grep({
                search = "@Component|@Service|@Repository|@Configuration",
                cwd = vim.fn.getcwd() .. "/src",
            })
        else
            local has_telescope, telescope = pcall(require, "telescope.builtin")
            if has_telescope then
                telescope.live_grep({
                    search_dirs = { vim.fn.getcwd() .. "/src" },
                    default_text = "@Component\\|@Service\\|@Repository\\|@Configuration",
                })
            else
                vim.notify("No fuzzy finder available. Install fzf-lua or telescope.", vim.log.levels.WARN)
            end
        end
    end, { desc = "Find Spring beans" })
    
    -- Command to find Spring controllers
    vim.api.nvim_create_user_command("SpringFindControllers", function()
        local has_fzf, fzf = pcall(require, "fzf-lua")
        if has_fzf then
            fzf.live_grep({
                search = "@Controller|@RestController",
                cwd = vim.fn.getcwd() .. "/src",
            })
        else
            local has_telescope, telescope = pcall(require, "telescope.builtin")
            if has_telescope then
                telescope.live_grep({
                    search_dirs = { vim.fn.getcwd() .. "/src" },
                    default_text = "@Controller\\|@RestController",
                })
            else
                vim.notify("No fuzzy finder available. Install fzf-lua or telescope.", vim.log.levels.WARN)
            end
        end
    end, { desc = "Find Spring controllers" })
end

return M
