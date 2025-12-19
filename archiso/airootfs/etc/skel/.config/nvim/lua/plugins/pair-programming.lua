-- ═══════════════════════════════════════════════════════════
--                  PAIR PROGRAMMING SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- Collaborative coding tools for remote pair programming
--
-- Features:
--   - Live Share functionality (instant.nvim)
--   - Code annotation and commenting
--   - Shared cursor positions
--   - Session management
--
-- ═══════════════════════════════════════════════════════════

return {
  -- Instant collaborative editing
  {
    "jbyuki/instant.nvim",
    cmd = {
      "InstantStartServer",
      "InstantStartSession",
      "InstantJoinSession",
      "InstantStatus",
      "InstantStop",
      "InstantFollow",
      "InstantStopFollow",
      "InstantStartSingle",
      "InstantJoinSingle",
    },
    keys = {
      { "<leader>Ps", "<cmd>InstantStartServer<cr>", desc = "Pair: Start Server" },
      { "<leader>PS", "<cmd>InstantStartSession<cr>", desc = "Pair: Start Session" },
      { "<leader>Pj", "<cmd>InstantJoinSession<cr>", desc = "Pair: Join Session" },
      { "<leader>Pf", "<cmd>InstantFollow<cr>", desc = "Pair: Follow Partner" },
      { "<leader>PF", "<cmd>InstantStopFollow<cr>", desc = "Pair: Stop Following" },
      { "<leader>Pt", "<cmd>InstantStatus<cr>", desc = "Pair: Session Status" },
      { "<leader>Pq", "<cmd>InstantStop<cr>", desc = "Pair: Stop Session" },
    },
    init = function()
      -- Session username (customize this)
      vim.g.instant_username = vim.fn.system("whoami"):gsub("%s+", "")
    end,
  },

  -- Enhanced commenting for pair programming
  {
    "numToStr/Comment.nvim",
    event = "VeryLazy",
    dependencies = {
      "JoosepAlviste/nvim-ts-context-commentstring",
    },
    keys = {
      { "gc", mode = { "n", "v" }, desc = "Comment: Toggle" },
      { "gb", mode = { "n", "v" }, desc = "Comment: Toggle Blockwise" },
      { "<leader>P/", "<cmd>lua require('Comment.api').toggle.linewise.current()<cr>", desc = "Pair: Toggle Comment" },
      {
        "<leader>P/",
        "<esc><cmd>lua require('Comment.api').toggle.linewise(vim.fn.visualmode())<cr>",
        mode = "v",
        desc = "Pair: Toggle Comment",
      },
    },
    config = function()
      require("Comment").setup({
        -- Add a space between comment and the line
        padding = true,

        -- Whether the cursor should stay at its position
        sticky = true,

        -- Lines to be ignored while (un)comment
        ignore = "^$",

        -- LHS of toggle mappings in NORMAL mode
        toggler = {
          line = "gcc",
          block = "gbc",
        },

        -- LHS of operator-pending mappings in NORMAL and VISUAL mode
        opleader = {
          line = "gc",
          block = "gb",
        },

        -- LHS of extra mappings
        extra = {
          above = "gcO",
          below = "gco",
          eol = "gcA",
        },

        -- Enable keybindings
        mappings = {
          basic = true,
          extra = true,
        },

        -- Function to call before (un)comment
        pre_hook = require("ts_context_commentstring.integrations.comment_nvim").create_pre_hook(),

        -- Function to call after (un)comment
        post_hook = nil,
      })
    end,
  },

  -- TODO comments highlighting (great for pair programming)
  {
    "folke/todo-comments.nvim",
    dependencies = { "nvim-lua/plenary.nvim" },
    event = "VeryLazy",
    keys = {
      { "<leader>Pt", "<cmd>TodoTelescope<cr>", desc = "Pair: Find TODOs" },
      { "<leader>Pn", "<cmd>lua require('todo-comments').jump_next()<cr>", desc = "Pair: Next TODO" },
      { "<leader>Pp", "<cmd>lua require('todo-comments').jump_prev()<cr>", desc = "Pair: Previous TODO" },
      { "<leader>Pl", "<cmd>TodoLocList<cr>", desc = "Pair: TODO Location List" },
      { "<leader>Pq", "<cmd>TodoQuickFix<cr>", desc = "Pair: TODO Quickfix" },
    },
    config = function()
      require("todo-comments").setup({
        signs = true,
        sign_priority = 8,

        -- Keywords recognized as todo comments
        keywords = {
          FIX = {
            icon = " ",
            color = "error",
            alt = { "FIXME", "BUG", "FIXIT", "ISSUE" },
          },
          TODO = { icon = " ", color = "info" },
          HACK = { icon = " ", color = "warning" },
          WARN = { icon = " ", color = "warning", alt = { "WARNING", "XXX" } },
          PERF = { icon = " ", alt = { "OPTIM", "PERFORMANCE", "OPTIMIZE" } },
          NOTE = { icon = " ", color = "hint", alt = { "INFO" } },
          TEST = { icon = "⏲ ", color = "test", alt = { "TESTING", "PASSED", "FAILED" } },
          -- Pair programming specific
          PAIR = { icon = " ", color = "info", alt = { "PAIRING", "REVIEW" } },
          QUESTION = { icon = " ", color = "warning", alt = { "ASK", "DISCUSS" } },
        },

        gui_style = {
          fg = "NONE",
          bg = "BOLD",
        },

        merge_keywords = true,
        highlight = {
          multiline = true,
          multiline_pattern = "^.",
          multiline_context = 10,
          before = "",
          keyword = "wide",
          after = "fg",
          pattern = [[.*<(KEYWORDS)\s*:]],
          comments_only = true,
          max_line_len = 400,
          exclude = {},
        },

        colors = {
          error = { "DiagnosticError", "ErrorMsg", "#DC2626" },
          warning = { "DiagnosticWarn", "WarningMsg", "#FBBF24" },
          info = { "DiagnosticInfo", "#2563EB" },
          hint = { "DiagnosticHint", "#10B981" },
          default = { "Identifier", "#7C3AED" },
          test = { "Identifier", "#FF00FF" },
        },

        search = {
          command = "rg",
          args = {
            "--color=never",
            "--no-heading",
            "--with-filename",
            "--line-number",
            "--column",
          },
          pattern = [[\b(KEYWORDS):]],
        },
      })
    end,
  },

  -- Git blame for pair programming (see who wrote what)
  {
    "f-person/git-blame.nvim",
    event = "VeryLazy",
    keys = {
      { "<leader>Pb", "<cmd>GitBlameToggle<cr>", desc = "Pair: Toggle Git Blame" },
      { "<leader>Po", "<cmd>GitBlameOpenCommitURL<cr>", desc = "Pair: Open Commit URL" },
      { "<leader>Pc", "<cmd>GitBlameCopySHA<cr>", desc = "Pair: Copy Commit SHA" },
      { "<leader>Pu", "<cmd>GitBlameCopyCommitURL<cr>", desc = "Pair: Copy Commit URL" },
    },
    init = function()
      vim.g.gitblame_enabled = 0 -- Disabled by default
      vim.g.gitblame_message_template = "  <author> • <date> • <summary>"
      vim.g.gitblame_date_format = "%r"
      vim.g.gitblame_highlight_group = "Comment"
      vim.g.gitblame_delay = 500
    end,
  },

  -- Multi-cursor editing (useful for pair programming)
  {
    "mg979/vim-visual-multi",
    event = "VeryLazy",
    keys = {
      { "<C-n>", mode = { "n", "v" }, desc = "Multi-cursor: Add cursor" },
      { "<C-Down>", mode = { "n", "v" }, desc = "Multi-cursor: Add cursor down" },
      { "<C-Up>", mode = { "n", "v" }, desc = "Multi-cursor: Add cursor up" },
    },
    init = function()
      vim.g.VM_theme = "iceblue"
      vim.g.VM_maps = {
        ["Find Under"] = "<C-n>",
        ["Find Subword Under"] = "<C-n>",
        ["Add Cursor Down"] = "<C-Down>",
        ["Add Cursor Up"] = "<C-Up>",
      }
    end,
  },

  -- Collaborative annotations
  {
    "danymat/neogen",
    cmd = "Neogen",
    dependencies = {
      "nvim-treesitter/nvim-treesitter",
      "L3MON4D3/LuaSnip",
    },
    keys = {
      { "<leader>Pa", "<cmd>Neogen<cr>", desc = "Pair: Generate Annotation" },
      { "<leader>Pf", "<cmd>Neogen func<cr>", desc = "Pair: Generate Function Doc" },
      { "<leader>Pc", "<cmd>Neogen class<cr>", desc = "Pair: Generate Class Doc" },
      { "<leader>Pt", "<cmd>Neogen type<cr>", desc = "Pair: Generate Type Doc" },
    },
    config = function()
      require("neogen").setup({
        enabled = true,
        snippet_engine = "luasnip",
        languages = {
          java = {
            template = {
              annotation_convention = "javadoc",
            },
          },
          kotlin = {
            template = {
              annotation_convention = "kdoc",
            },
          },
          typescript = {
            template = {
              annotation_convention = "tsdoc",
            },
          },
          javascript = {
            template = {
              annotation_convention = "jsdoc",
            },
          },
          c = {
            template = {
              annotation_convention = "doxygen",
            },
          },
          cpp = {
            template = {
              annotation_convention = "doxygen",
            },
          },
        },
      })
    end,
  },

  -- Which-key integration for pair programming
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>P", group = "pair-programming", icon = " " },
      },
    },
  },
}
