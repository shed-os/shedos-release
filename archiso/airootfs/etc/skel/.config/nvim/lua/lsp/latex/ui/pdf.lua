-- PDF Viewer Integration
local M = {}

function M.setup()
    -- Auto-open PDF after successful build
    vim.api.nvim_create_autocmd("User", {
        pattern = "TexlabBuildSuccess",
        callback = function()
            vim.notify("LaTeX build successful", vim.log.levels.INFO)
        end,
    })
    
    vim.api.nvim_create_autocmd("User", {
        pattern = "TexlabBuildFailed",
        callback = function()
            vim.notify("LaTeX build failed. Check logs.", vim.log.levels.ERROR)
        end,
    })
end

M.setup()
return M
