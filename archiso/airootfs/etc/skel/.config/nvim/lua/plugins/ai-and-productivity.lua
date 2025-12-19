-- ═══════════════════════════════════════════════════════════
--              ULTIMATE EXPERIENCE - PHASE 1
-- ═══════════════════════════════════════════════════════════
--
-- Game-changing features that beat ALL major IDEs
-- These are the MUST-HAVE plugins for the ultimate experience
--
-- ═══════════════════════════════════════════════════════════

return {

  -- ═══════════════════════════════════════════════════════════
  -- 🤖 AI CODING ASSISTANT (Better than VSCode Copilot)
  -- ═══════════════════════════════════════════════════════════

  -- Copilot - AI completion (DISABLED - upgrade dialog spam)
  {
    "zbirenbaum/copilot.lua",
    enabled = false,
    cmd = "Copilot",
    event = "InsertEnter",
    opts = {
      suggestion = {
        enabled = true,
        auto_trigger = true,
        keymap = {
          accept = "<M-l>",      -- Alt+l to accept
          accept_word = "<M-w>", -- Alt+w to accept word
          accept_line = "<M-j>", -- Alt+j to accept line
          next = "<M-]>",        -- Alt+] for next suggestion
          prev = "<M-[>",        -- Alt+[ for previous
          dismiss = "<C-]>",     -- Ctrl+] to dismiss
        },
      },
      panel = {
        enabled = true,
        auto_refresh = true,
        keymap = {
          jump_prev = "[[",
          jump_next = "]]",
          accept = "<CR>",
          refresh = "gr",
          open = "<M-CR>", -- Alt+Enter to open panel
        },
      },
      filetypes = {
        yaml = true,
        markdown = true,
        help = false,
        gitcommit = true,
        gitrebase = false,
        ["."] = true,
      },
    },
  },

  -- Copilot Chat - AI conversation interface (DISABLED - depends on copilot.lua)
  {
    "CopilotC-Nvim/CopilotChat.nvim",
    enabled = false,
    branch = "canary",
    dependencies = {
      "zbirenbaum/copilot.lua",
      "nvim-lua/plenary.nvim",
    },
    cmd = {
      "CopilotChat",
      "CopilotChatOpen",
      "CopilotChatToggle",
      "CopilotChatExplain",
      "CopilotChatReview",
      "CopilotChatFix",
      "CopilotChatOptimize",
      "CopilotChatDocs",
      "CopilotChatTests",
    },
    keys = {
      { "<leader>ai", "<cmd>CopilotChatToggle<cr>", desc = "AI Chat Toggle" },
      { "<leader>ae", "<cmd>CopilotChatExplain<cr>", desc = "AI Explain" },
      { "<leader>ar", "<cmd>CopilotChatReview<cr>", desc = "AI Review" },
      { "<leader>af", "<cmd>CopilotChatFix<cr>", desc = "AI Fix" },
      { "<leader>ao", "<cmd>CopilotChatOptimize<cr>", desc = "AI Optimize" },
      { "<leader>ad", "<cmd>CopilotChatDocs<cr>", desc = "AI Docs" },
      { "<leader>at", "<cmd>CopilotChatTests<cr>", desc = "AI Tests" },
    },
    opts = {
      question_header = "## User ",
      answer_header = "## Copilot ",
      error_header = "## Error ",
      separator = "───",
      show_help = true,
      auto_follow_cursor = true,
      mappings = {
        complete = {
          detail = "Use @<Tab> or /<Tab> for options.",
          insert = "<Tab>",
        },
        close = {
          normal = "q",
          insert = "<C-c>",
        },
        reset = {
          normal = "<C-r>",
          insert = "<C-r>",
        },
        submit_prompt = {
          normal = "<CR>",
          insert = "<C-s>",
        },
        accept_diff = {
          normal = "<C-y>",
          insert = "<C-y>",
        },
        yank_diff = {
          normal = "gy",
        },
        show_diff = {
          normal = "gd",
        },
        show_system_prompt = {
          normal = "gp",
        },
        show_user_selection = {
          normal = "gs",
        },
      },
    },
  },

  -- Claude Code - Official Claude Code CLI integration (uses claude.ai subscription!)
  {
    "coder/claudecode.nvim",
    dependencies = {
      "folke/snacks.nvim",
    },
    config = true,
    keys = {
      { "<leader>a", nil, desc = "AI/Claude Code" },
      { "<leader>ac", "<cmd>ClaudeCode<cr>", desc = "Claude: Toggle" },
      { "<leader>af", "<cmd>ClaudeCodeFocus<cr>", desc = "Claude: Focus" },
      { "<leader>ar", "<cmd>ClaudeCode --resume<cr>", desc = "Claude: Resume" },
      { "<leader>aC", "<cmd>ClaudeCode --continue<cr>", desc = "Claude: Continue" },
      { "<leader>am", "<cmd>ClaudeCodeSelectModel<cr>", desc = "Claude: Select Model" },
      { "<leader>ab", "<cmd>ClaudeCodeAdd %<cr>", desc = "Claude: Add Buffer" },
      { "<leader>as", "<cmd>ClaudeCodeSend<cr>", mode = "v", desc = "Claude: Send Selection" },
      { "<leader>aa", "<cmd>ClaudeCodeDiffAccept<cr>", desc = "Claude: Accept Diff" },
      { "<leader>ad", "<cmd>ClaudeCodeDiffDeny<cr>", desc = "Claude: Deny Diff" },
    },
  },

  -- ═══════════════════════════════════════════════════════════
  -- ⚡ HARPOON 2 - INSTANT FILE JUMPING (Life-Changing)
  -- ═══════════════════════════════════════════════════════════

  {
    "ThePrimeagen/harpoon",
    branch = "harpoon2",
    dependencies = { "nvim-lua/plenary.nvim" },
    keys = {
      {
        "<leader>ha",
        function()
          require("harpoon"):list():add()
          vim.notify("File harpooned!", vim.log.levels.INFO)
        end,
        desc = "Harpoon: Add file",
      },
      {
        "<leader>he",
        function()
          local harpoon = require("harpoon")
          harpoon.ui:toggle_quick_menu(harpoon:list())
        end,
        desc = "Harpoon: Toggle menu",
      },
      {
        "<leader>h1",
        function()
          require("harpoon"):list():select(1)
        end,
        desc = "Harpoon: File 1",
      },
      {
        "<leader>h2",
        function()
          require("harpoon"):list():select(2)
        end,
        desc = "Harpoon: File 2",
      },
      {
        "<leader>h3",
        function()
          require("harpoon"):list():select(3)
        end,
        desc = "Harpoon: File 3",
      },
      {
        "<leader>h4",
        function()
          require("harpoon"):list():select(4)
        end,
        desc = "Harpoon: File 4",
      },
      {
        "<C-S-P>",
        function()
          require("harpoon"):list():prev()
        end,
        desc = "Harpoon: Previous",
      },
      {
        "<C-S-N>",
        function()
          require("harpoon"):list():next()
        end,
        desc = "Harpoon: Next",
      },
    },
    opts = {
      settings = {
        save_on_toggle = true,
        sync_on_ui_close = true,
        key = function()
          return vim.loop.cwd()
        end,
      },
    },
  },

  -- ═══════════════════════════════════════════════════════════
  -- 🎯 FLASH.NVIM - TELEPORT NAVIGATION (Magical)
  -- ═══════════════════════════════════════════════════════════

  {
    "folke/flash.nvim",
    event = "VeryLazy",
    opts = {
      labels = "asdfghjklqwertyuiopzxcvbnm",
      search = {
        multi_window = true,
        forward = true,
        wrap = true,
        mode = "exact",
      },
      jump = {
        jumplist = true,
        pos = "start",
        history = true,
        register = false,
        nohlsearch = true,
        autojump = false,
      },
      label = {
        uppercase = true,
        rainbow = {
          enabled = true,
          shade = 5,
        },
      },
      modes = {
        search = {
          enabled = true,
        },
        char = {
          enabled = true,
          jump_labels = true,
          multi_line = true,
        },
      },
    },
    keys = {
      {
        "s",
        mode = { "n", "x", "o" },
        function()
          require("flash").jump()
        end,
        desc = "Flash",
      },
      {
        "S",
        mode = { "n", "x", "o" },
        function()
          require("flash").treesitter()
        end,
        desc = "Flash Treesitter",
      },
      {
        "r",
        mode = "o",
        function()
          require("flash").remote()
        end,
        desc = "Remote Flash",
      },
      {
        "R",
        mode = { "o", "x" },
        function()
          require("flash").treesitter_search()
        end,
        desc = "Treesitter Search",
      },
      {
        "<c-s>",
        mode = { "c" },
        function()
          require("flash").toggle()
        end,
        desc = "Toggle Flash Search",
      },
    },
  },

  -- ═══════════════════════════════════════════════════════════
  -- 🎨 NOICE.NVIM - BEAUTIFUL UI (Wow Factor)
  -- ═══════════════════════════════════════════════════════════

  {
    "folke/noice.nvim",
    event = "VeryLazy",
    dependencies = {
      "MunifTanjim/nui.nvim",
      "rcarriga/nvim-notify",
    },
    opts = {
      lsp = {
        override = {
          ["vim.lsp.util.convert_input_to_markdown_lines"] = true,
          ["vim.lsp.util.stylize_markdown"] = true,
          ["cmp.entry.get_documentation"] = true,
        },
        hover = {
          enabled = true,
          silent = false,
        },
        signature = {
          enabled = true,
          auto_open = {
            enabled = true,
            trigger = true,
            luasnip = true,
            throttle = 50,
          },
        },
        message = {
          enabled = true,
        },
        documentation = {
          view = "hover",
          opts = {
            lang = "markdown",
            replace = true,
            render = "plain",
            format = { "{message}" },
            win_options = { concealcursor = "n", conceallevel = 3 },
          },
        },
      },
      presets = {
        bottom_search = true,         -- Use bottom for search
        command_palette = true,        -- Position the cmdline and popupmenu together
        long_message_to_split = true,  -- Long messages in split
        inc_rename = true,             -- Enable inc-rename.nvim integration
        lsp_doc_border = true,         -- Border for hover docs and signature help
      },
      messages = {
        enabled = true,
        view = "notify",
        view_error = "notify",
        view_warn = "notify",
        view_history = "messages",
        view_search = "virtualtext",
      },
      popupmenu = {
        enabled = true,
        backend = "nui",
      },
      notify = {
        enabled = true,
        view = "notify",
      },
      routes = {
        {
          filter = {
            event = "msg_show",
            kind = "",
            find = "written",
          },
          opts = { skip = true },
        },
      },
    },
    keys = {
      {
        "<leader>sn",
        function()
          require("noice").cmd("history")
        end,
        desc = "Noice: Message History",
      },
      {
        "<leader>sl",
        function()
          require("noice").cmd("last")
        end,
        desc = "Noice: Last Message",
      },
      {
        "<leader>sd",
        function()
          require("noice").cmd("dismiss")
        end,
        desc = "Noice: Dismiss All",
      },
      {
        "<c-f>",
        function()
          if not require("noice.lsp").scroll(4) then
            return "<c-f>"
          end
        end,
        silent = true,
        expr = true,
        desc = "Scroll forward",
        mode = { "i", "n", "s" },
      },
      {
        "<c-b>",
        function()
          if not require("noice.lsp").scroll(-4) then
            return "<c-b>"
          end
        end,
        silent = true,
        expr = true,
        desc = "Scroll backward",
        mode = { "i", "n", "s" },
      },
    },
  },

  -- Enhanced notifications
  {
    "rcarriga/nvim-notify",
    opts = {
      timeout = 3000,
      max_height = function()
        return math.floor(vim.o.lines * 0.75)
      end,
      max_width = function()
        return math.floor(vim.o.columns * 0.75)
      end,
      stages = "fade_in_slide_out",
      render = "wrapped-compact",
      background_colour = "#000000",
      icons = {
        ERROR = "",
        WARN = "",
        INFO = "",
        DEBUG = "",
        TRACE = "✎",
      },
    },
  },

  -- ═══════════════════════════════════════════════════════════
  -- 🔀 NEOGIT - ULTIMATE GIT WORKFLOW
  -- ═══════════════════════════════════════════════════════════

  {
    "NeogitOrg/neogit",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "sindrets/diffview.nvim",
      "nvim-telescope/telescope.nvim",
    },
    cmd = "Neogit",
    keys = {
      { "<leader>gg", "<cmd>Neogit<cr>", desc = "Neogit: Open" },
      { "<leader>gc", "<cmd>Neogit commit<cr>", desc = "Neogit: Commit" },
      { "<leader>gp", "<cmd>Neogit push<cr>", desc = "Neogit: Push" },
      { "<leader>gl", "<cmd>Neogit pull<cr>", desc = "Neogit: Pull" },
      { "<leader>gb", "<cmd>Neogit branch<cr>", desc = "Neogit: Branch" },
    },
    opts = {
      kind = "tab",
      signs = {
        section = { "", "" },
        item = { "", "" },
        hunk = { "", "" },
      },
      integrations = {
        telescope = true,
        diffview = true,
      },
      sections = {
        untracked = {
          folded = false,
          hidden = false,
        },
        unstaged = {
          folded = false,
          hidden = false,
        },
        staged = {
          folded = false,
          hidden = false,
        },
        stashes = {
          folded = true,
          hidden = false,
        },
        unpulled = {
          folded = true,
          hidden = false,
        },
        unmerged = {
          folded = false,
          hidden = false,
        },
        recent = {
          folded = true,
          hidden = false,
        },
      },
    },
  },

  -- Diffview for beautiful diffs
  {
    "sindrets/diffview.nvim",
    cmd = {
      "DiffviewOpen",
      "DiffviewClose",
      "DiffviewToggleFiles",
      "DiffviewFocusFiles",
      "DiffviewRefresh",
      "DiffviewFileHistory",
    },
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Diffview: Open" },
      { "<leader>gh", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview: File History" },
      { "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "Diffview: Branch History" },
    },
    opts = {
      enhanced_diff_hl = true,
      use_icons = true,
    },
  },

  -- Git blame inline
  {
    "f-person/git-blame.nvim",
    event = "VeryLazy",
    opts = {
      enabled = true,
      message_template = " <author> • <date> • <summary>",
      date_format = "%r",
      virtual_text_column = 80,
    },
    keys = {
      { "<leader>gB", "<cmd>GitBlameToggle<cr>", desc = "Git: Toggle Blame" },
    },
  },
}
