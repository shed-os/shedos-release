-- Shell LSP Entry Point
local M = {}
local helpers = require("lsp.helpers")

function M.setup()
    helpers.safe_require("lsp.shell.core.bashls")
    helpers.safe_setup("lsp.shell.features.shellcheck")
    helpers.safe_setup("lsp.shell.features.shfmt")
    helpers.safe_setup("lsp.shell.ui.runner")
    helpers.safe_setup("lsp.shell.utils.completion")

    vim.notify("Shell LSP setup complete", vim.log.levels.INFO)
end

vim.api.nvim_create_autocmd("FileType", {
    pattern = { "sh", "bash", "zsh" },
    callback = function() M.setup() end,
    once = true,
})

return M
