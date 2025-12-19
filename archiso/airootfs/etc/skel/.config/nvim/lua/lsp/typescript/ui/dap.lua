-- TypeScript DAP Configuration
local M = {}
function M.setup()
    local dap = require("dap")
    dap.adapters.node2 = {
        type = "executable",
        command = "node",
        args = { vim.fn.stdpath("data") .. "/mason/packages/node-debug2-adapter/out/src/nodeDebug.js" },
    }
    dap.configurations.typescript = {
        {
            name = "Launch",
            type = "node2",
            request = "launch",
            program = "${file}",
            cwd = vim.fn.getcwd(),
            sourceMaps = true,
            protocol = "inspector",
            console = "integratedTerminal",
        },
    }
    dap.configurations.javascript = dap.configurations.typescript
end
return M
