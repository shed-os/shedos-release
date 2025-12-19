-- Android Development Support
local M = {}
function M.setup()
    vim.api.nvim_create_user_command("AndroidBuild", function()
        vim.cmd("!./gradlew assembleDebug")
    end, { desc = "Build Android app" })
end
return M
