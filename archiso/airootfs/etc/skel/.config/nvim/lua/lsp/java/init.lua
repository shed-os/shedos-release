-- ═══════════════════════════════════════════════════════════
--                    JAVA LSP ENTRY POINT
-- ═══════════════════════════════════════════════════════════
--
-- This file serves as the entry point for all Java language support.
-- It coordinates the loading of core LSP, features, UI, and utilities.
--
-- Enable/disable Java support by uncommenting/commenting the require
-- statement in lua/lsp/init.lua
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Check if Java is installed
local function check_java_installation()
    local java_version = vim.fn.system("java -version 2>&1 | head -n 1")
    if vim.v.shell_error ~= 0 then
        vim.notify("Java not found! Please install Java 17 or later.", vim.log.levels.ERROR)
        return false
    end
    return true
end

-- Use shared helpers for consistency
local helpers = require("lsp.helpers")

-- Setup function called when Java filetype is detected
function M.setup()
    if not check_java_installation() then
        return
    end

    -- Load Java utilities first (needed by other modules)
    helpers.safe_setup("lsp.java.utils.workspace")
    helpers.safe_setup("lsp.java.utils.classpath")
    helpers.safe_setup("lsp.java.utils.decompiler")
    helpers.safe_setup("lsp.java.utils.profiler")

    -- Load core Java LSP configuration
    -- Note: core/jdtls.lua is loaded via ftplugin/java.lua for proper per-buffer setup
    -- paths.lua doesn't have setup, it just exports functions
    helpers.safe_require("lsp.java.core.paths")
    helpers.safe_setup("lsp.java.core.lombok")

    -- Load DAP with protected call (may not be loaded yet by Lazy.nvim)
    helpers.safe_setup("lsp.java.core.dap")

    -- Load Java features
    helpers.safe_setup("lsp.java.features.spring")
    helpers.safe_setup("lsp.java.features.spring-boot")
    helpers.safe_setup("lsp.java.features.quarkus")
    helpers.safe_setup("lsp.java.features.maven")
    helpers.safe_setup("lsp.java.features.gradle")
    helpers.safe_setup("lsp.java.features.testing")
    helpers.safe_setup("lsp.java.features.refactoring")
    helpers.safe_setup("lsp.java.features.code-actions")
    helpers.safe_setup("lsp.java.features.live-templates")
    helpers.safe_setup("lsp.java.features.jpa") -- JPA Buddy++

    -- Load UI enhancements
    helpers.safe_setup("lsp.java.ui.dap-ui")
    helpers.safe_setup("lsp.java.ui.test-ui")
    helpers.safe_setup("lsp.java.ui.hierarchy")
    helpers.safe_setup("lsp.java.ui.documentation")

    vim.notify("Java LSP setup complete", vim.log.levels.INFO)
end

-- Auto-setup on Java filetype
vim.api.nvim_create_autocmd("FileType", {
    pattern = "java",
    callback = function()
        M.setup()
    end,
    once = true,
})

return M
