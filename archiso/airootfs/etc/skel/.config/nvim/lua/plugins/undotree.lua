-- ═══════════════════════════════════════════════════════════
--                    UNDO TREE VISUALIZATION
-- ═══════════════════════════════════════════════════════════
--
-- Visualize your undo history as a tree
-- Never lose work - see and restore any previous state!
--
-- ═══════════════════════════════════════════════════════════

return {
  "mbbill/undotree",
  cmd = "UndotreeToggle",
  keys = {
    { "<leader>u", "<cmd>UndotreeToggle<cr>", desc = "Undo Tree" },
  },
  config = function()
    -- Configure undotree
    vim.g.undotree_WindowLayout = 2 -- Layout style
    vim.g.undotree_ShortIndicators = 1 -- Use short time indicators
    vim.g.undotree_SetFocusWhenToggle = 1 -- Focus undotree when opened
    vim.g.undotree_DiffpanelHeight = 10 -- Diff panel height
    vim.g.undotree_SplitWidth = 30 -- Undo tree width
    vim.g.undotree_DiffAutoOpen = 1 -- Auto open diff panel
    vim.g.undotree_HelpLine = 1 -- Show help line
    vim.g.undotree_HighlightChangedText = 1 -- Highlight changed text
    vim.g.undotree_HighlightSyntaxAdd = "DiffAdd" -- Highlight for additions
    vim.g.undotree_HighlightSyntaxChange = "DiffChange" -- Highlight for changes
    vim.g.undotree_HighlightSyntaxDel = "DiffDelete" -- Highlight for deletions
  end,
}
