-- Quarkus Support
local M = {}

function M.is_quarkus_project()
    local pom = vim.fn.getcwd() .. "/pom.xml"
    if vim.fn.filereadable(pom) == 1 then
        local content = vim.fn.readfile(pom)
        for _, line in ipairs(content) do
            if line:match("quarkus") then return true end
        end
    end
    return false
end

function M.setup()
    if not M.is_quarkus_project() then return end
    vim.notify("Quarkus project detected", vim.log.levels.INFO)
    
    vim.api.nvim_create_user_command("QuarkusDev", function()
        vim.cmd("!mvn quarkus:dev")
    end, { desc = "Run Quarkus in dev mode" })
    
    vim.api.nvim_create_user_command("QuarkusTest", function()
        vim.cmd("!mvn quarkus:test")
    end, { desc = "Run Quarkus continuous testing" })
end

return M
