-- ═══════════════════════════════════════════════════════════
--        DISABLE CONFLICTING LAZYVIM EXTRAS
-- ═══════════════════════════════════════════════════════════
--
-- This file explicitly disables LazyVim extras that conflict
-- with our custom configurations (LSP, editor, etc.)
--
-- These extras are already removed from lazyvim.json, but this
-- provides an additional layer of protection to ensure they
-- never get re-enabled accidentally.
--
-- ═══════════════════════════════════════════════════════════

return {
  -- Disable conflicting extras by marking them as not enabled
  -- This prevents them from loading even if they somehow get imported

  -- ═══════════════════════════════════════════════════════════
  -- LANGUAGE EXTRAS
  -- ═══════════════════════════════════════════════════════════

  -- C/C++ - We have custom setup with clangd, cpptools, cpplint
  { import = "lazyvim.plugins.extras.lang.clangd", enabled = false },

  -- Go - We have custom setup with gopls, golangci-lint, delve
  { import = "lazyvim.plugins.extras.lang.go", enabled = false },

  -- Kotlin - We have custom setup with kotlin-language-server, ktlint
  { import = "lazyvim.plugins.extras.lang.kotlin", enabled = false },

  -- Markdown - We have custom setup with marksman, prettier, render-markdown
  { import = "lazyvim.plugins.extras.lang.markdown", enabled = false },

  -- Python - We have custom setup with pyright, ruff-lsp, black, isort, flake8
  { import = "lazyvim.plugins.extras.lang.python", enabled = false },

  -- Rust - We have custom setup with rustaceanvim, crates.nvim, codelldb
  { import = "lazyvim.plugins.extras.lang.rust", enabled = false },

  -- TypeScript - We have custom setup with tsserver, eslint, prettier
  { import = "lazyvim.plugins.extras.lang.typescript", enabled = false },

  -- SQL - We have custom setup with sqls, sqlfluff
  { import = "lazyvim.plugins.extras.lang.sql", enabled = false },

  -- JSON - We have custom setup with jsonls, SchemaStore in data.lua
  { import = "lazyvim.plugins.extras.lang.json", enabled = false },

  -- YAML - We have custom setup with yamlls, SchemaStore in data.lua
  -- NOTE: Setting enabled = false is NOT enough because this is a "recommended" extra
  -- We must also override the server config to prevent auto-setup
  { import = "lazyvim.plugins.extras.lang.yaml", enabled = false },

  -- Override yamlls server config to prevent LazyVim from auto-configuring it
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        yamlls = false, -- Disable LazyVim's yamlls setup completely
      },
    },
  },

  -- TailwindCSS - We have custom setup in web.lua
  { import = "lazyvim.plugins.extras.lang.tailwind", enabled = false },

  -- LaTeX - We have custom setup with vimtex, texlab
  { import = "lazyvim.plugins.extras.lang.tex", enabled = false },

  -- Java - We have custom setup with jdtls, Spring Boot, Maven, Gradle
  { import = "lazyvim.plugins.extras.lang.java", enabled = false },
}
