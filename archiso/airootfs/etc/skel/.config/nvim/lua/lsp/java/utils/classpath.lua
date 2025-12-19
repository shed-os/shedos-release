-- Classpath Utilities
local M = {}

function M.show_classpath()
    vim.notify("Classpath: See JDTLS logs", vim.log.levels.INFO)
end

function M.setup()
    vim.api.nvim_create_user_command("JavaShowClasspath", function()
        M.show_classpath()
    end, { desc = "Show Java classpath" })
end

return M
