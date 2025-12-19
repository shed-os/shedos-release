-- Zig Formatter
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("ZigFormat", function()
        vim.cmd("!zig fmt %")
    end, { desc = "Format Zig file" })
    
    -- Auto-format on save
    vim.api.nvim_create_autocmd("BufWritePre", {
        pattern = "*.zig",
        callback = function()
            vim.cmd("silent !zig fmt %")
            vim.cmd("edit")
        end,
    })
end

M.setup()
return M
