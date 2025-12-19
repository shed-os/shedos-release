-- Zig Testing Support
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("ZigTest", function()
        vim.cmd("!zig test %")
    end, { desc = "Run Zig tests" })
    
    vim.api.nvim_create_user_command("ZigTestAll", function()
        vim.cmd("!zig build test")
    end, { desc = "Run all Zig tests" })
end

M.setup()
return M
