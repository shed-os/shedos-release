-- ═══════════════════════════════════════════════════════════
--                    JAVA DEBUG ADAPTER PROTOCOL
-- ═══════════════════════════════════════════════════════════
--
-- Complete debugging support for Java applications including:
-- - Breakpoints (line, conditional, logpoints)
-- - Step debugging (over, into, out)
-- - Variable inspection and modification
-- - Stack trace navigation
-- - Hot code replacement
-- - Remote debugging
-- - Spring Boot debugging
-- - JUnit/TestNG debugging
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- DAP configuration for Java
function M.setup()
    local dap = require("dap")

    -- ═══════════════════════════════════════════════════════
    --                    DAP ADAPTERS
    -- ═══════════════════════════════════════════════════════

    dap.adapters.java = function(callback)
        -- JDTLS will automatically configure the debug adapter
        -- This is handled by nvim-jdtls
        callback({
            type = "server",
            host = "127.0.0.1",
            port = "${port}",
        })
    end

    -- ═══════════════════════════════════════════════════════
    --                    DAP CONFIGURATIONS
    -- ═══════════════════════════════════════════════════════

    dap.configurations.java = {
        -- Launch Java application
        {
            type = "java",
            request = "launch",
            name = "Debug (Launch) - Current File",
            mainClass = "${file}",
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            stopOnEntry = false,
            args = "",
            vmArgs = "",
        },

        -- Launch with arguments
        {
            type = "java",
            request = "launch",
            name = "Debug (Launch) with Arguments",
            mainClass = "${file}",
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            stopOnEntry = false,
            args = function()
                local args_string = vim.fn.input("Program arguments: ")
                return vim.split(args_string, " ", { trimempty = true })
            end,
            vmArgs = function()
                local vm_args_string = vim.fn.input("VM arguments: ")
                return vm_args_string
            end,
        },

        -- Launch main class
        {
            type = "java",
            request = "launch",
            name = "Debug (Launch) - Main Class",
            mainClass = function()
                return vim.fn.input("Main class: ", "", "file")
            end,
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
        },

        -- Attach to running process
        {
            type = "java",
            request = "attach",
            name = "Debug (Attach) - Remote",
            hostName = function()
                return vim.fn.input("Host name: ", "localhost")
            end,
            port = function()
                return tonumber(vim.fn.input("Port: ", "5005"))
            end,
            projectName = "${workspaceFolderBasename}",
        },

        -- Spring Boot application
        {
            type = "java",
            request = "launch",
            name = "Spring Boot - Run",
            mainClass = function()
                -- Auto-detect Spring Boot main class
                local spring_main = M.find_spring_boot_main()
                if spring_main then
                    return spring_main
                end
                return vim.fn.input("Main class: ", "", "file")
            end,
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            vmArgs = "-Dspring.profiles.active=dev",
        },

        -- Spring Boot with profile
        {
            type = "java",
            request = "launch",
            name = "Spring Boot - Run with Profile",
            mainClass = function()
                local spring_main = M.find_spring_boot_main()
                if spring_main then
                    return spring_main
                end
                return vim.fn.input("Main class: ", "", "file")
            end,
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            vmArgs = function()
                local profile = vim.fn.input("Spring profile: ", "dev")
                return "-Dspring.profiles.active=" .. profile
            end,
        },

        -- Quarkus application
        {
            type = "java",
            request = "launch",
            name = "Quarkus - Dev Mode",
            mainClass = "io.quarkus.runner.GeneratedMain",
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            env = {
                QUARKUS_PROFILE = "dev",
            },
        },

        -- JUnit test - Single
        {
            type = "java",
            request = "launch",
            name = "Debug (JUnit Test) - Current Test",
            mainClass = "",
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            testKind = "junit",
        },

        -- JUnit test - All in class
        {
            type = "java",
            request = "launch",
            name = "Debug (JUnit Test) - All in Class",
            mainClass = "",
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            testKind = "junit",
        },

        -- TestNG test
        {
            type = "java",
            request = "launch",
            name = "Debug (TestNG Test)",
            mainClass = "",
            projectName = "${workspaceFolderBasename}",
            cwd = "${workspaceFolder}",
            console = "integratedTerminal",
            testKind = "testng",
        },
    }

    -- ═══════════════════════════════════════════════════════
    --                    DAP SIGNS
    -- ═══════════════════════════════════════════════════════

    vim.fn.sign_define("DapBreakpoint", {
        text = " ",
        texthl = "DiagnosticError",
        linehl = "",
        numhl = "DiagnosticError",
    })

    vim.fn.sign_define("DapBreakpointCondition", {
        text = " ",
        texthl = "DiagnosticWarn",
        linehl = "",
        numhl = "DiagnosticWarn",
    })

    vim.fn.sign_define("DapBreakpointRejected", {
        text = " ",
        texthl = "DiagnosticError",
        linehl = "",
        numhl = "DiagnosticError",
    })

    vim.fn.sign_define("DapLogPoint", {
        text = " ",
        texthl = "DiagnosticInfo",
        linehl = "",
        numhl = "DiagnosticInfo",
    })

    vim.fn.sign_define("DapStopped", {
        text = " ",
        texthl = "DiagnosticHint",
        linehl = "DapStoppedLine",
        numhl = "DiagnosticHint",
    })

    -- ═══════════════════════════════════════════════════════
    --                    JAVA DAP KEYMAPS
    -- ═══════════════════════════════════════════════════════

    vim.keymap.set("n", "<F5>", function()
        require("dap").continue()
    end, { desc = "Debug: Continue" })

    vim.keymap.set("n", "<F10>", function()
        require("dap").step_over()
    end, { desc = "Debug: Step Over" })

    vim.keymap.set("n", "<F11>", function()
        require("dap").step_into()
    end, { desc = "Debug: Step Into" })

    vim.keymap.set("n", "<F12>", function()
        require("dap").step_out()
    end, { desc = "Debug: Step Out" })

    vim.keymap.set("n", "<leader>db", function()
        require("dap").toggle_breakpoint()
    end, { desc = "Toggle Breakpoint" })

    vim.keymap.set("n", "<leader>dB", function()
        require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: "))
    end, { desc = "Set Conditional Breakpoint" })

    vim.keymap.set("n", "<leader>dL", function()
        require("dap").set_breakpoint(nil, nil, vim.fn.input("Log point message: "))
    end, { desc = "Set Log Point" })

    vim.keymap.set("n", "<leader>dr", function()
        require("dap").repl.open()
    end, { desc = "Open REPL" })

    vim.keymap.set("n", "<leader>dl", function()
        require("dap").run_last()
    end, { desc = "Run Last" })

    vim.keymap.set("n", "<leader>dt", function()
        require("dap").terminate()
    end, { desc = "Terminate Debug Session" })

    vim.keymap.set("n", "<leader>du", function()
        require("dapui").toggle()
    end, { desc = "Toggle Debug UI" })

    vim.keymap.set({ "n", "v" }, "<leader>dh", function()
        require("dap.ui.widgets").hover()
    end, { desc = "Debug: Hover" })

    vim.keymap.set({ "n", "v" }, "<leader>dp", function()
        require("dap.ui.widgets").preview()
    end, { desc = "Debug: Preview" })

    vim.keymap.set("n", "<leader>df", function()
        local widgets = require("dap.ui.widgets")
        widgets.centered_float(widgets.frames)
    end, { desc = "Debug: Frames" })

    vim.keymap.set("n", "<leader>ds", function()
        local widgets = require("dap.ui.widgets")
        widgets.centered_float(widgets.scopes)
    end, { desc = "Debug: Scopes" })

    -- ═══════════════════════════════════════════════════════
    --                    JAVA DAP COMMANDS
    -- ═══════════════════════════════════════════════════════

    vim.api.nvim_create_user_command("DapJavaLaunch", function()
        require("dap").continue()
    end, { desc = "Launch Java debug session" })

    vim.api.nvim_create_user_command("DapJavaAttach", function()
        local host = vim.fn.input("Host: ", "localhost")
        local port = tonumber(vim.fn.input("Port: ", "5005"))

        require("dap").run({
            type = "java",
            request = "attach",
            hostName = host,
            port = port,
        })
    end, { desc = "Attach to remote Java process" })

    vim.api.nvim_create_user_command("DapJavaSpringBoot", function()
        local spring_main = M.find_spring_boot_main()
        if not spring_main then
            vim.notify("Spring Boot main class not found", vim.log.levels.ERROR)
            return
        end

        require("dap").run({
            type = "java",
            request = "launch",
            mainClass = spring_main,
            projectName = vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
        })
    end, { desc = "Launch Spring Boot application" })
end

-- ═══════════════════════════════════════════════════════════
--                    UTILITY FUNCTIONS
-- ═══════════════════════════════════════════════════════════

-- Find Spring Boot main class
function M.find_spring_boot_main()
    local root_dir = vim.fn.getcwd()

    -- Search for @SpringBootApplication annotation
    local find_cmd = string.format(
        'find "%s" -name "*.java" -type f -exec grep -l "@SpringBootApplication" {} \\;',
        root_dir
    )

    local output = vim.fn.system(find_cmd)
    local files = vim.split(output, "\n", { trimempty = true })

    if #files == 0 then
        return nil
    end

    -- Extract fully qualified class name from the first match
    local main_file = files[1]
    local content = vim.fn.readfile(main_file)

    local package_name = ""
    local class_name = ""

    for _, line in ipairs(content) do
        if line:match("^package%s+") then
            package_name = line:match("^package%s+([%w%.]+);")
        elseif line:match("@SpringBootApplication") then
            -- Find next class declaration
            for i = _ + 1, #content do
                local class_line = content[i]
                if class_line:match("public%s+class%s+") then
                    class_name = class_line:match("public%s+class%s+(%w+)")
                    break
                end
            end
            break
        end
    end

    if package_name ~= "" and class_name ~= "" then
        return package_name .. "." .. class_name
    end

    return nil
end

-- Hot code replacement (HCR) setup
function M.setup_hot_code_replace()
    -- Enable hot code replacement for Java debugging
    local dap = require("dap")

    dap.defaults.java.hotcodereplace = "auto"

    -- Command to manually trigger HCR
    vim.api.nvim_create_user_command("DapJavaHotSwap", function()
        vim.notify("Applying hot code replacement...", vim.log.levels.INFO)
        require("jdtls.dap").setup_dap_main_class_configs()
    end, { desc = "Apply Java hot code replacement" })
end

-- Remote debugging helper
function M.setup_remote_debugging()
    vim.api.nvim_create_user_command("DapJavaRemote", function(opts)
        local host = opts.args ~= "" and opts.args or "localhost:5005"
        local parts = vim.split(host, ":")
        local hostname = parts[1]
        local port = tonumber(parts[2] or "5005")

        require("dap").run({
            type = "java",
            request = "attach",
            hostName = hostname,
            port = port,
            projectName = vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
        })

        vim.notify(string.format("Attaching to %s:%d", hostname, port), vim.log.levels.INFO)
    end, {
        nargs = "?",
        desc = "Attach to remote Java process (host:port)",
    })
end

-- Initialize DAP for Java
function M.init()
    M.setup()
    M.setup_hot_code_replace()
    M.setup_remote_debugging()
end

return M
