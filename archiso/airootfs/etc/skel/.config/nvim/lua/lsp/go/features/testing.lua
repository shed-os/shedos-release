-- Go Testing Support
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("GoTest", function()
        vim.cmd("!go test ./...")
    end, { desc = "Run Go tests" })
    
    vim.api.nvim_create_user_command("GoTestFile", function()
        vim.cmd("!go test %")
    end, { desc = "Test current file" })
    
    vim.api.nvim_create_user_command("GoTestFunc", function()
        local func_name = vim.fn.expand("<cword>")
        vim.cmd("!go test -run " .. func_name)
    end, { desc = "Test function under cursor" })
    
    vim.api.nvim_create_user_command("GoCoverage", function()
        vim.cmd("!go test -cover ./...")
    end, { desc = "Go test coverage" })
end

M.setup()
return M
