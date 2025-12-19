-- Crates.io Integration
local M = {}

function M.setup()
    -- Integration with crates.nvim plugin for Cargo.toml management
    vim.api.nvim_create_user_command("RustCratesUpdate", function()
        vim.notify("Use crates.nvim plugin for dependency management", vim.log.levels.INFO)
    end, { desc = "Update crates info" })
end

M.setup()
return M
