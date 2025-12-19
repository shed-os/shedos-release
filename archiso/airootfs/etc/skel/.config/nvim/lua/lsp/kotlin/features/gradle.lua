-- Kotlin Gradle Support
local M = {}
function M.setup()
    vim.api.nvim_create_user_command("KotlinGradleBuild", function()
        vim.cmd("!./gradlew build")
    end, { desc = "Gradle build Kotlin project" })
end
return M
