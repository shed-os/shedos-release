-- MONKEY PATCH: Sience [LSP] Format request failed errors
-- This wraps the native format function to ensure a capable client exists
-- before attempting to format, preventing the noisy error message.
-- PLACEMENT CRITICAL: This must run before ANY plugin loads to capture the original function.
local _original_format = vim.lsp.buf.format
vim.lsp.buf.format = function(opts)
  opts = opts or {}
  local bufnr = opts.bufnr or vim.api.nvim_get_current_buf()
  local clients = vim.lsp.get_clients({ bufnr = bufnr })
  
  -- Filter for clients that support formatting
  local capable_clients = vim.tbl_filter(function(client)
    return client.supports_method("textDocument/formatting")
  end, clients)

  if #capable_clients == 0 then
    -- SILENT EXIT: Do not notify.
    return
  end

  -- If we have capable clients, rely on the original function to do the heavy lifting
  -- BUT we pass the specific filter to it so it doesn't complain
  opts.id = nil
  opts.name = nil
  opts.filter = function(client)
     return client.supports_method("textDocument/formatting")
  end
  
  return _original_format(opts)
end

-- Load error handler first to suppress non-critical transient errors
require("config.error-handler")



-- Performance optimizations (load first for best results)
-- Performance optimizations (load first for best results)
require("config.performance").setup()

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
-- require("lsp") -- DISABLED: Migrated to lua/plugins/ structures

-- Load C/C++ specific autocmds (fixes formatting issues)
require("config.c-cpp-autocmds")

-- Load unified test runner keymaps
require("config.test-keymaps")

-- Load screenshot keymaps last to override any LazyVim defaults
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    vim.schedule(function()
      pcall(require, "config.screenshot-keymaps")
    end)
  end,
})
