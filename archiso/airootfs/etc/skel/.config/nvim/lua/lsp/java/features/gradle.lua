-- Gradle Support
local M = {}

function M.is_gradle_project()
    local cwd = vim.fn.getcwd()
    return vim.fn.filereadable(cwd .. "/build.gradle") == 1 or 
           vim.fn.filereadable(cwd .. "/build.gradle.kts") == 1
end

function M.setup()
    if not M.is_gradle_project() then return end
    
    vim.api.nvim_create_user_command("GradleBuild", function()
        vim.cmd("!./gradlew build")
    end, { desc = "Gradle build" })
    
    vim.api.nvim_create_user_command("GradleTest", function()
        vim.cmd("!./gradlew test")
    end, { desc = "Gradle test" })
    
    vim.api.nvim_create_user_command("GradleClean", function()
        vim.cmd("!./gradlew clean")
    end, { desc = "Gradle clean" })
end

return M
