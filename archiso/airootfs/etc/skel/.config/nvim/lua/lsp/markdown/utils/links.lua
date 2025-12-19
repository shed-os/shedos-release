-- Markdown Link Utilities
local M = {}

function M.setup()
    -- Follow links with gx or <CR>
    vim.keymap.set("n", "<CR>", function()
        -- Will be enhanced by plugins like markdown-preview
    end, { buffer = true, desc = "Follow link" })
end

M.setup()
return M
