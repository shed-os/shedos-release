-- Zig Build System Integration
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("ZigBuild", function()
        vim.cmd("!zig build")
    end, { desc = "Zig build" })
    
    vim.api.nvim_create_user_command("ZigRun", function()
        vim.cmd("!zig build run")
    end, { desc = "Zig build and run" })
    
    vim.api.nvim_create_user_command("ZigCheck", function()
        vim.cmd("!zig build check")
    end, { desc = "Zig build check" })
    
    vim.api.nvim_create_user_command("ZigClean", function()
        vim.cmd("!rm -rf zig-out zig-cache")
    end, { desc = "Clean Zig build artifacts" })
end

M.setup()
return M
