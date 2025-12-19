-- Rust language plugin configuration
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, { "rust", "toml" })
    end,
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, {
        "rust-analyzer",
        "codelldb",
        "taplo",
      })
    end,
  },

  -- nvim-dap (Debug Adapter Protocol)
  {
    "mfussenegger/nvim-dap",
    lazy = true,
    config = function()
      -- DAP configuration is handled by lua/lsp/rust/core/dap.lua
    end,
  },

  -- nvim-dap-ui
  {
    "rcarriga/nvim-dap-ui",
    lazy = true,
    dependencies = { "mfussenegger/nvim-dap", "nvim-neotest/nvim-nio" },
    config = function()
      -- DAP UI configuration is handled by lua/lsp/rust/ui/dap-ui.lua
    end,
  },

  -- Rust tools (optional but recommended)
  {
    "mrcjkb/rustaceanvim",
    version = "^5",
    ft = { "rust" },
    dependencies = {
      "nvim-lua/plenary.nvim",
      "mfussenegger/nvim-dap",
      "rcarriga/nvim-dap-ui",
    },
    opts = {
      server = {
        on_attach = function(client, bufnr)
          -- Custom keymaps can be added here
        end,
        capabilities = require("lsp.utils").get_capabilities(),
        settings = {
          ["rust-analyzer"] = {
            cargo = {
              allFeatures = true,
              loadOutDirsFromCheck = true,
              buildScripts = {
                enable = true,
              },
            },
            checkOnSave = {
              allFeatures = true,
              command = "clippy",
              extraArgs = { "--no-deps" },
            },
            procMacro = {
              enable = true,
              ignored = {
                ["async-trait"] = { "async_trait" },
                ["napi-derive"] = { "napi" },
                ["async-recursion"] = { "async_recursion" },
              },
            },
          },
        },
      },
    },
    config = function(_, opts)
      vim.g.rustaceanvim = vim.tbl_deep_extend("keep", vim.g.rustaceanvim or {}, opts or {})
    end,
  },

  {
    "Saecki/crates.nvim",
    event = { "BufRead Cargo.toml" },
    dependencies = { "nvim-lua/plenary.nvim" },
    config = function()
      require("crates").setup({
        null_ls = { enabled = true, name = "crates.nvim" },
      })
    end,
  },

  {
    "nvim-neotest/neotest",
    dependencies = { "rouge8/neotest-rust" },
    opts = function(_, opts)
      opts.adapters = opts.adapters or {}
      table.insert(opts.adapters, require("neotest-rust"))
    end,
  },
}
