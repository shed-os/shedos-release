-- Kotlin Language Server Configuration
local M = {}

function M.setup()
    -- Configure kotlin_language_server to use Java 21 from mise
    -- Your system Java is 25, but kotlin compiler doesn't support it yet
    --
    -- Solution: Use wrapper script that sets JAVA_HOME to Java 21
    -- Wrapper: ~/.local/bin/kotlin-language-server-java21
    -- This ensures Java 21 is used only for Kotlin LSP
    -- Your Spring Boot projects still use Java 25

    local lspconfig = require("lspconfig")
    local wrapper_path = vim.fn.expand("~/.local/bin/kotlin-language-server-java21")

    -- Check if wrapper exists
    if vim.fn.executable(wrapper_path) == 0 then
        vim.notify(
            "kotlin-language-server wrapper not found at " .. wrapper_path,
            vim.log.levels.WARN
        )
        return
    end

    lspconfig.kotlin_language_server.setup({
        cmd = { wrapper_path },
        capabilities = require("lsp.utils").get_capabilities(),
        on_attach = function(client, bufnr)
            vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr })
            vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr })
            vim.keymap.set("n", "<leader>ca", vim.lsp.buf.code_action, { buffer = bufnr })
        end,
    })
end

M.setup()
return M
