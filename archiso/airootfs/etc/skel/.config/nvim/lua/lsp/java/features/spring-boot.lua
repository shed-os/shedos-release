-- Spring Boot Support
local M = {}

M.annotations = {
    "@SpringBootApplication", "@EnableAutoConfiguration", "@SpringBootConfiguration",
    "@ConditionalOnProperty", "@ConditionalOnClass", "@ConditionalOnMissingBean",
    "@ConfigurationProperties", "@EnableConfigurationProperties",
}

function M.is_spring_boot_project()
    local pom = vim.fn.getcwd() .. "/pom.xml"
    if vim.fn.filereadable(pom) == 1 then
        local content = vim.fn.readfile(pom)
        for _, line in ipairs(content) do
            if line:match("spring%-boot%-starter") then return true end
        end
    end
    return false
end

function M.setup()
    if not M.is_spring_boot_project() then return end
    vim.notify("Spring Boot project detected", vim.log.levels.INFO)
    
    vim.api.nvim_create_user_command("SpringBootRun", function()
        vim.cmd("!mvn spring-boot:run")
    end, { desc = "Run Spring Boot application" })
    
    vim.api.nvim_create_user_command("SpringBootDevtools", function()
        vim.notify("Enable spring-boot-devtools in pom.xml for hot reload", vim.log.levels.INFO)
    end, { desc = "Spring Boot devtools info" })
end

return M
