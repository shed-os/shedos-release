return {
  {
    "stevearc/conform.nvim",
    event = { "BufReadPre", "BufNewFile" },
    opts = {
      -- Define global formatting options
      default_format_opts = {
        timeout_ms = 3000,
        async = false,
        quiet = true, -- Suppress all output
        lsp_format = "never", -- CRITICAL: Do not fallback globally. Enable per-language.
      },
      -- Suppress notifications when no formatter is found
      notify_on_error = false,
      notify_no_formatters = false,
      format_on_save = nil, -- Ensure we don't override LazyVim's autoformat

      -- Custom Formatter Configurations
      formatters = {
        stylua = {
          prepend_args = { "--config-path", vim.fn.expand("~/.config/nvim/.stylua.toml") },
        },
        sqlfluff = {
          args = { "format", "--dialect=ansi", "-" }, -- Note: sqlfluff formatting can be slow
        },
      },

      -- Configure formatters
      formatters_by_ft = {
        lua = { "stylua" },
        
        -- Web
        javascript = { "prettierd", "prettier", stop_after_first = true },
        javascriptreact = { "prettierd", "prettier", stop_after_first = true },
        typescript = { "prettierd", "prettier", stop_after_first = true },
        typescriptreact = { "prettierd", "prettier", stop_after_first = true },
        vue = { "prettierd", "prettier", stop_after_first = true },
        css = { "prettierd", "prettier", stop_after_first = true },
        scss = { "prettierd", "prettier", stop_after_first = true },
        less = { "prettierd", "prettier", stop_after_first = true },
        html = { "prettierd", "prettier", stop_after_first = true },
        json = { "prettierd", "prettier", stop_after_first = true },
        jsonc = { "prettierd", "prettier", stop_after_first = true },
        yaml = { "prettierd", "prettier", stop_after_first = true },
        markdown = { "prettierd", "prettier", stop_after_first = true },
        graphql = { "prettierd", "prettier", stop_after_first = true },
        handlebars = { "prettierd", "prettier", stop_after_first = true },
        
        -- Python
        python = { "isort", "black" },
        
        -- Shell
        sh = { "shfmt" },
        bash = { "shfmt" },
        zsh = { "shfmt" },
        
        -- C/C++ (Prefer clang-format > LSP)
        c = { "clang_format", lsp_format = "fallback" },
        cpp = { "clang_format", lsp_format = "fallback" },
        cmake = { "cmakelang" },
        
        -- Go
        go = { "goimports", "gofumpt", lsp_format = "fallback" },
        
        -- Java (Google Format > LSP)
        java = { "google-java-format", lsp_format = "fallback" }, 
        
        -- Terraform
        terraform = { "terraform_fmt" },
        tf = { "terraform_fmt" },
        
        -- SQL
        sql = { "sqlfluff" },
        
        -- XML
        xml = { "xmlformatter" },

        -- Languages that must rely ONLY on LSP (no Mason formatter available/requested)
        rust = { lsp_format = "fallback" }, 
        kotlin = { lsp_format = "fallback" },

        -- Fallback for everything else
        ["_"] = { "trim_whitespace" },
      },
    },
  },
}
