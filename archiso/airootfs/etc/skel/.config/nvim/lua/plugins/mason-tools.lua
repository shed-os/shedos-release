return {
  -- Core Mason Plugin (ensure it loads)
  { "mason-org/mason.nvim" },

  -- Dedicated Tool Installer (The "Right Way" for bulk installs)
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = { "mason-org/mason.nvim" },
    opts = {
      -- Automatically update tools on startup
      auto_update = true,
      
      -- Run installation immediately on startup
      run_on_start = true,
      
      -- Start installation verification after 3s (avoids UI freeze)
      start_delay = 3000, 

      -- The definitive list of tools to install
      ensure_installed = {
         -- LSPs
        "angular-language-server",
        "ansible-language-server",
        "asm-lsp",
        "awk-language-server",
        "azure-pipelines-language-server",
        "bash-language-server",
        "clangd",
        "cmake-language-server",
        "css-lsp",
        "css-variables-language-server",
        "cssmodules-language-server",
        "cucumber-language-server",
        "deno",
        "docker-compose-language-service",
        "docker-language-server",
        "dockerfile-language-server",
        "emmet-ls",
        "eslint-lsp",
        "gh-actions-language-server",
        "gopls",
        "gradle-language-server",
        "helm-ls",
        "html-lsp",
        "htmx-lsp",
        "jdtls",
        "jq-lsp",
        "json-lsp",
        "jsonld-lsp",
        "kotlin-language-server",
        "lua-language-server",
        "marksman",
        "neocmakelsp",
        "nextls",
        "nginx-language-server",
        "postgres-language-server",
        "pyright",
        "ruff",
        "rust-analyzer",
        "sqls",
        "svelte-language-server",
        "taplo",
        "terraform-ls",
        "texlab",
        "typescript-language-server",
        "vtsls",
        "vue-language-server",
        "yaml-language-server",
        "zls",
        
        -- Linters
        "ansible-lint",
        "checkstyle",
        "cmakelint",
        "cpplint",
        "eslint_d",
        "flake8",
        "golangci-lint",
        "hadolint",
        "htmlhint",
        "jsonlint",
        "ktlint",
        "markdownlint",
        "markdownlint-cli2",
        "ruff",
        "shellcheck",
        "sqlfluff",
        "stylelint",
        "tflint",
        "yamllint",
        
        -- Formatters
        "asmfmt",
        "black",
        "clang-format",
        "cmakelang",
        "gofumpt",
        "goimports",
        "google-java-format",
        "htmlbeautifier",
        "isort",
        "jq",
        "json-to-struct",
        "latexindent",
        "markdown-toc",
        "nginx-config-formatter",
        "prettier",
        "prettierd",
        "shfmt",
        "stylua",
        "yamlfmt",
        
        -- Debuggers (DAP)
        "bash-debug-adapter",
        "codelldb",
        "cpptools",
        "debugpy",
        "delve",
        "java-debug-adapter",
        "java-test",
        "js-debug-adapter",
        "kotlin-debug-adapter",
        
        -- Tools
        "gh",
        "gotests",
      },
    },
    config = function(_, opts)
      require("mason-tool-installer").setup(opts)
      -- Optional: Trigger a check immediately (though run_on_start does this)
      -- vim.cmd("MasonToolsInstall") 
    end,
  },
}
