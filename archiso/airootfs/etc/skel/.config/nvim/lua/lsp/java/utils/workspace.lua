-- Java Workspace Management
local M = {}

function M.clean_workspace()
    local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace"
    vim.fn.delete(workspace_dir, "rf")
    vim.notify("Java workspace cleaned", vim.log.levels.INFO)
end

function M.setup()
    vim.api.nvim_create_user_command("JavaCleanWorkspace", function()
        M.clean_workspace()
    end, { desc = "Clean Java workspace" })
end

return M
