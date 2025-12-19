-- Load error handler first to suppress non-critical transient errors
require("config.error-handler")

-- Performance optimizations (load first for best results)
-- TEMPORARILY DISABLED FOR TESTING
-- require("config.performance").setup()

-- bootstrap lazy.nvim, LazyVim and your plugins
require("config.lazy")
require("lsp")

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
