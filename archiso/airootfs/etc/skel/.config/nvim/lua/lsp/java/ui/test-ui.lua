-- Test UI for Java
local M = {}

function M.setup()
    -- Neotest integration for Java tests
    local neotest = require("neotest")
    
    vim.keymap.set("n", "<leader>tt", function()
        neotest.run.run()
    end, { desc = "Run nearest test" })
    
    vim.keymap.set("n", "<leader>tf", function()
        neotest.run.run(vim.fn.expand("%"))
    end, { desc = "Run file tests" })
    
    vim.keymap.set("n", "<leader>ts", function()
        neotest.summary.toggle()
    end, { desc = "Toggle test summary" })
end

return M
