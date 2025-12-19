-- ═══════════════════════════════════════════════════════════
--                    LSP CAPABILITIES UTILITY
-- ═══════════════════════════════════════════════════════════
--
-- Handles capabilities for both blink.cmp and nvim-cmp
-- Compatible with LazyVim 14.x+ and Neovim 0.11.2+
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Get LSP capabilities compatible with current completion engine
function M.get_capabilities()
    local has_blink, blink = pcall(require, "blink.cmp")
    local has_cmp, cmp_nvim_lsp = pcall(require, "cmp_nvim_lsp")
    
    -- Start with default capabilities
    local capabilities = vim.lsp.protocol.make_client_capabilities()
    
    -- Enhance with blink.cmp if available (LazyVim 14.x+)
    if has_blink then
        capabilities = blink.get_lsp_capabilities(capabilities)
        return capabilities
    end
    
    -- Fallback to nvim-cmp if available
    if has_cmp then
        capabilities = cmp_nvim_lsp.default_capabilities(capabilities)
        return capabilities
    end
    
    -- Return basic capabilities if neither is available
    return capabilities
end

-- Check if we're using blink.cmp
function M.using_blink()
    return pcall(require, "blink.cmp")
end

-- Check if we're using nvim-cmp
function M.using_nvim_cmp()
    return pcall(require, "cmp_nvim_lsp")
end

return M
