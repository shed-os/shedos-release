-- ═══════════════════════════════════════════════════════════
--          LEGENDARY - ENHANCED COMMAND PALETTE
-- ═══════════════════════════════════════════════════════════
--
-- Searchable command palette (like VSCode Cmd+Shift+P)
--
-- Features:
--   - Find keymaps, commands, autocmds, and functions
--   - Fuzzy search across all definitions
--   - Execute commands directly
--   - Works alongside which-key
--
-- ═══════════════════════════════════════════════════════════

return {
  "mrjones2014/legendary.nvim",
  priority = 10000,
  lazy = false,
  keys = {
    {
      "<leader>fL",
      "<cmd>Legendary<cr>",
      desc = "Legendary (Command Palette)",
    },
    {
      "<C-p>",
      "<cmd>Legendary<cr>",
      desc = "Legendary (Command Palette)",
    },
  },
  dependencies = {
    "kkharji/sqlite.lua",
  },
  config = function()
    require("legendary").setup({
      -- Keymaps are automatically pulled from which-key
      -- No need to duplicate keymaps here
      extensions = {
        lazy_nvim = true,
        which_key = {
          auto_register = true,
          do_binding = false,
          use_groups = true,
        },
      },

      -- UI configuration
      select_prompt = "Legendary",
      include_builtin = true,
      include_legendary_cmds = true,

      -- Sorting
      sort = {
        -- Sort by frecency (frequent + recent)
        most_recent_first = true,
        user_items_first = true,
        frecency = {
          -- Boost recently used items
          db_root = vim.fn.stdpath("data") .. "/legendary/",
          max_timestamps = 10,
        },
      },

      -- Scratchpad for quick temporary commands
      scratchpad = {
        view = "float",
        results_view = "float",
        keep_contents = true,
      },

      -- Cache for performance
      cache_path = vim.fn.stdpath("cache") .. "/legendary/",

      -- Icons
      icons = {
        keymap = " ",
        command = " ",
        fn = " ",
        itemgroup = " ",
      },

      -- Custom commands to add to palette
      commands = {
        {
          ":LazyUpdate",
          description = "Update all plugins",
        },
        {
          ":LazySync",
          description = "Sync plugins (clean + update)",
        },
        {
          ":Mason",
          description = "Open Mason (LSP/tool installer)",
        },
        {
          ":MasonUpdate",
          description = "Update all Mason packages",
        },
        {
          ":Lazy profile",
          description = "Show plugin startup profile",
        },
        {
          ":checkhealth",
          description = "Run Neovim health check",
        },
        {
          ":LspInfo",
          description = "Show LSP client status",
        },
        {
          ":LspLog",
          description = "Open LSP log file",
        },
        {
          ":Telescope",
          description = "Open Telescope picker",
        },
        {
          ":ConformInfo",
          description = "Show formatter status",
        },
        {
          ":Neogit",
          description = "Open Neogit (Git UI)",
        },
        {
          ":DiffviewOpen",
          description = "Open Git diff view",
        },
      },

      -- Custom functions to add to palette
      funcs = {
        {
          function()
            vim.cmd("nohlsearch")
            vim.notify("Search highlight cleared", vim.log.levels.INFO)
          end,
          description = "Clear search highlight",
        },
        {
          function()
            local buf_count = #vim.fn.getbufinfo({ buflisted = 1 })
            vim.notify("Open buffers: " .. buf_count, vim.log.levels.INFO)
          end,
          description = "Count open buffers",
        },
        {
          function()
            vim.cmd("write")
            vim.cmd("source %")
            vim.notify("File saved and sourced", vim.log.levels.INFO)
          end,
          description = "Save and source current file",
        },
        {
          function()
            -- Copy current file path to clipboard
            local filepath = vim.fn.expand("%:p")
            vim.fn.setreg("+", filepath)
            vim.notify("Copied: " .. filepath, vim.log.levels.INFO)
          end,
          description = "Copy file path to clipboard",
        },
        {
          function()
            -- Copy current file name to clipboard
            local filename = vim.fn.expand("%:t")
            vim.fn.setreg("+", filename)
            vim.notify("Copied: " .. filename, vim.log.levels.INFO)
          end,
          description = "Copy file name to clipboard",
        },
        {
          function()
            -- Delete all buffers except current
            vim.cmd("%bd|e#|bd#")
            vim.notify("All buffers deleted except current", vim.log.levels.WARN)
          end,
          description = "Delete all buffers except current",
        },
        {
          function()
            -- Reload all buffers
            vim.cmd("bufdo e")
            vim.notify("All buffers reloaded", vim.log.levels.INFO)
          end,
          description = "Reload all buffers from disk",
        },
        {
          function()
            -- Show current file info
            local info = {
              "File: " .. vim.fn.expand("%:p"),
              "Type: " .. vim.bo.filetype,
              "Encoding: " .. vim.bo.fileencoding,
              "Format: " .. vim.bo.fileformat,
              "Lines: " .. vim.fn.line("$"),
            }
            vim.notify(table.concat(info, "\n"), vim.log.levels.INFO)
          end,
          description = "Show current file info",
        },
      },

      -- Autocmds to show in palette
      autocmds = {
        {
          name = "AutoSaveLspFormat",
          clear = true,
          {
            "BufWritePre",
            vim.lsp.buf.format,
            description = "Format on save (LSP)",
          },
        },
      },
    })
  end,
}
