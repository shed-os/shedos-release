-- Kotlin DAP Configuration
local M = {}
function M.setup()
    local dap = require("dap")
    dap.adapters.kotlin = {
        type = "executable",
        command = "kotlin-debug-adapter",
    }
    dap.configurations.kotlin = {
        {
            type = "kotlin",
            request = "launch",
            name = "Kotlin Debug",
            mainClass = function()
                return vim.fn.input("Main class: ")
            end,
        },
    }
end
return M
