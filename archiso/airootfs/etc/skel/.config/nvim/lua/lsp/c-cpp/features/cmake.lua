-- CMake Support
local M = {}
function M.setup()
    vim.api.nvim_create_user_command("CMakeBuild", function()
        vim.cmd("!cmake --build build")
    end, { desc = "CMake build" })
end
return M
