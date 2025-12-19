-- ═══════════════════════════════════════════════════════════
--           BLINK.CMP CONFIGURATION
-- ═══════════════════════════════════════════════════════════
--
-- Configure blink.cmp (LazyVim's default completion engine)
-- to work with vim-dadbod-completion for SQL files
--
-- ═══════════════════════════════════════════════════════════

return {
  {
    "saghen/blink.cmp",
    optional = true,
    opts = function(_, opts)
      -- Ensure sources table exists
      opts.sources = opts.sources or {}
      opts.sources.providers = opts.sources.providers or {}

      -- Add vim-dadbod-completion as a provider
      opts.sources.providers.dadbod = {
        name = "vim-dadbod-completion",
        module = "vim_dadbod_completion.blink",
        score_offset = 85, -- Prioritize dadbod completions
      }

      -- Add per-filetype configuration
      opts.sources.per_filetype = opts.sources.per_filetype or {}

      -- Enable dadbod completion for SQL files
      opts.sources.per_filetype.sql = { "dadbod", "lsp", "path", "buffer" }
      opts.sources.per_filetype.mysql = { "dadbod", "lsp", "path", "buffer" }
      opts.sources.per_filetype.plsql = { "dadbod", "lsp", "path", "buffer" }

      return opts
    end,
  },
}
