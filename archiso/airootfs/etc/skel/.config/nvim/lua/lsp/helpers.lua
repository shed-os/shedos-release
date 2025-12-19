-- ═══════════════════════════════════════════════════════════
--                    LSP HELPER UTILITIES
-- ═══════════════════════════════════════════════════════════
--
-- Shared helper functions for all LSP configurations
-- Provides defensive programming patterns to prevent errors
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Safely load and setup a module
-- Prevents crashes when plugins aren't loaded yet or modules have errors
function M.safe_setup(module_path)
    local ok, module = pcall(require, module_path)
    if ok and module.setup then
        local setup_ok, err = pcall(module.setup)
        if not setup_ok then
            vim.notify(
                string.format("Failed to setup %s: %s", module_path, err),
                vim.log.levels.WARN
            )
            return false
        end
        return true
    elseif ok and module.init then
        -- Some modules use .init() instead of .setup()
        local init_ok, err = pcall(module.init)
        if not init_ok then
            vim.notify(
                string.format("Failed to init %s: %s", module_path, err),
                vim.log.levels.WARN
            )
            return false
        end
        return true
    elseif not ok then
        -- Module failed to load - could be normal if plugin not installed
        vim.notify(
            string.format("Module %s not available: %s", module_path, module),
            vim.log.levels.DEBUG
        )
        return false
    end

    -- Module loaded but has no setup/init function - just load it
    return true
end

-- Safely require a module without calling setup
function M.safe_require(module_path)
    local ok, module = pcall(require, module_path)
    if not ok then
        vim.notify(
            string.format("Failed to load %s: %s", module_path, module),
            vim.log.levels.WARN
        )
        return nil
    end
    return module
end

-- Check if a command exists
function M.command_exists(cmd)
    return vim.fn.executable(cmd) == 1
end

-- Check if a plugin is loaded
function M.plugin_loaded(plugin_name)
    local ok = pcall(require, plugin_name)
    return ok
end

-- Create autocmd with error handling
function M.safe_autocmd(event, pattern, callback, opts)
    opts = opts or {}
    local safe_callback = function(...)
        local ok, err = pcall(callback, ...)
        if not ok then
            vim.notify(
                string.format("Autocmd error for %s: %s", table.concat(pattern, ","), err),
                vim.log.levels.ERROR
            )
        end
    end

    vim.api.nvim_create_autocmd(event, vim.tbl_extend("force", opts, {
        pattern = pattern,
        callback = safe_callback,
    }))
end

return M
