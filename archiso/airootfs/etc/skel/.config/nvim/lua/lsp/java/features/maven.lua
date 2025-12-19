-- Maven Support
local M = {}

function M.is_maven_project()
    return vim.fn.filereadable(vim.fn.getcwd() .. "/pom.xml") == 1
end

function M.setup()
    if not M.is_maven_project() then return end
    
    vim.api.nvim_create_user_command("MavenCompile", function()
        vim.cmd("!mvn clean compile")
    end, { desc = "Maven clean compile" })
    
    vim.api.nvim_create_user_command("MavenTest", function()
        vim.cmd("!mvn test")
    end, { desc = "Maven test" })
    
    vim.api.nvim_create_user_command("MavenPackage", function()
        vim.cmd("!mvn package")
    end, { desc = "Maven package" })
    
    vim.api.nvim_create_user_command("MavenInstall", function()
        vim.cmd("!mvn install")
    end, { desc = "Maven install" })
end

return M
