-- Rust Testing Support
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("RustTest", function()
        vim.cmd("!cargo test")
    end, { desc = "Run Cargo tests" })
    
    vim.api.nvim_create_user_command("RustTestFile", function()
        local file = vim.fn.expand("%:t:r")
        vim.cmd("!cargo test --lib " .. file)
    end, { desc = "Test current file" })
    
    vim.api.nvim_create_user_command("RustBench", function()
        vim.cmd("!cargo bench")
    end, { desc = "Run benchmarks" })
end

M.setup()
return M
