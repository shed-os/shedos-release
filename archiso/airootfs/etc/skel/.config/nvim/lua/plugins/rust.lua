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
          local opts = { buffer = bufnr, silent = true }
          
          -- Custom User Keymaps
          vim.keymap.set("n", "<leader>rb", "<cmd>RustBuild<CR>", 
              vim.tbl_extend("force", opts, { desc = "Cargo build" }))
          vim.keymap.set("n", "<leader>rr", "<cmd>RustRun<CR>", 
              vim.tbl_extend("force", opts, { desc = "Cargo run" }))
          vim.keymap.set("n", "<leader>rt", "<cmd>RustTest<CR>", 
              vim.tbl_extend("force", opts, { desc = "Cargo test" }))
          vim.keymap.set("n", "<leader>rc", "<cmd>RustCheck<CR>", 
              vim.tbl_extend("force", opts, { desc = "Cargo check" }))
          vim.keymap.set("n", "<leader>rf", "<cmd>RustFmt<CR>", 
              vim.tbl_extend("force", opts, { desc = "Rust format" }))
          
          -- Rust-analyzer specific actions
          vim.keymap.set("n", "<leader>rh", function()
              vim.cmd("RustLsp hover actions")
          end, vim.tbl_extend("force", opts, { desc = "Hover actions" }))
          
          vim.keymap.set("n", "<leader>re", function()
              vim.cmd("RustLsp expandMacro")
          end, vim.tbl_extend("force", opts, { desc = "Expand macro" }))
        end,
        default_settings = {
          -- rust-analyzer language server configuration
          ["rust-analyzer"] = {
            cargo = {
              allFeatures = true,
              loadOutDirsFromCheck = true,
              buildScripts = {
                enable = true,
              },
              runBuildScripts = true,
            },
            checkOnSave = true,
            check = {
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
            inlayHints = {
              bindingModeHints = {
                enable = false,
              },
              chainingHints = {
                enable = false,
              },
              closingBraceHints = {
                enable = false,
                minLines = 25,
              },
              closureReturnTypeHints = {
                enable = "never",
              },
              lifetimeElisionHints = {
                enable = "never",
                useParameterNames = false,
              },
              maxLength = 25,
              parameterHints = {
                enable = false,
              },
              reborrowHints = {
                enable = "never",
              },
              renderColons = true,
              typeHints = {
                enable = false,
                hideClosureInitialization = false,
                hideNamedConstructor = false,
              },
            },
            lens = {
                enable = true,
                run = { enable = true },
                debug = { enable = true },
                implementations = { enable = true },
                references = {
                    adt = { enable = true },
                    enumVariant = { enable = true },
                    method = { enable = true },
                    trait = { enable = true },
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
