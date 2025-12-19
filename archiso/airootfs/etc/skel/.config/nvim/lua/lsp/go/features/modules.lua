-- Go Modules Support
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("GoModInit", function()
        local module_name = vim.fn.input("Module name: ")
        vim.cmd("!go mod init " .. module_name)
    end, { desc = "Initialize Go module" })
    
    vim.api.nvim_create_user_command("GoModTidy", function()
        vim.cmd("!go mod tidy")
    end, { desc = "Tidy Go module" })
    
    vim.api.nvim_create_user_command("GoGet", function()
        local package = vim.fn.input("Package: ")
        vim.cmd("!go get " .. package)
    end, { desc = "Go get package" })
end

M.setup()
return M
