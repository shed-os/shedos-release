-- JUnit/TestNG Testing Support
local M = {}

function M.setup()
    vim.api.nvim_create_user_command("JavaTestClass", function()
        require("jdtls").test_class()
    end, { desc = "Test Java class" })
    
    vim.api.nvim_create_user_command("JavaTestMethod", function()
        require("jdtls").test_nearest_method()
    end, { desc = "Test Java method" })
end

return M
