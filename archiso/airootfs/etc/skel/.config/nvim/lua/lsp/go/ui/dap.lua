-- Go DAP Configuration
local M = {}

function M.setup()
    local dap = require("dap")
    
    dap.adapters.go = {
        type = "server",
        port = "${port}",
        executable = {
            command = vim.fn.stdpath("data") .. "/mason/bin/dlv",
            args = { "dap", "-l", "127.0.0.1:${port}" },
        },
    }
    
    dap.configurations.go = {
        {
            type = "go",
            name = "Debug",
            request = "launch",
            program = "${file}",
        },
        {
            type = "go",
            name = "Debug test",
            request = "launch",
            mode = "test",
            program = "${file}",
        },
        {
            type = "go",
            name = "Debug Package",
            request = "launch",
            program = "${fileDirname}",
        },
    }
end

return M
