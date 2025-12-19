-- Cargo Integration
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("RustBuild", function()
        vim.cmd("!cargo build")
    end, { desc = "Cargo build" })
    
    vim.api.nvim_create_user_command("RustRun", function()
        vim.cmd("!cargo run")
    end, { desc = "Cargo run" })
    
    vim.api.nvim_create_user_command("RustCheck", function()
        vim.cmd("!cargo check")
    end, { desc = "Cargo check" })
    
    vim.api.nvim_create_user_command("RustClippy", function()
        vim.cmd("!cargo clippy")
    end, { desc = "Cargo clippy" })
    
    vim.api.nvim_create_user_command("RustDoc", function()
        vim.cmd("!cargo doc --open")
    end, { desc = "Open Rust documentation" })
    
    vim.api.nvim_create_user_command("RustUpdate", function()
        vim.cmd("!cargo update")
    end, { desc = "Update Cargo dependencies" })
end

M.setup()
return M
