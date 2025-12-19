-- ═══════════════════════════════════════════════════════════
--              TELESCOPE - ENHANCED FUZZY FINDER
-- ═══════════════════════════════════════════════════════════
--
-- Supercharge Telescope with powerful extensions
--
-- Extensions:
--   1. fzf-native: 10-50x faster fuzzy finding (requires compilation)
--   2. ui-select: Better code actions and LSP selections
--   3. file-browser: Advanced file management
--   4. project: Quick project switching
--   5. frecency: Smart file history (frequent + recent)
--
-- ═══════════════════════════════════════════════════════════

return {
  {
    "nvim-telescope/telescope.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",

      -- FZF native (CRITICAL for performance)
      {
        "nvim-telescope/telescope-fzf-native.nvim",
        build = "make",
        cond = function()
          return vim.fn.executable("make") == 1
        end,
      },

      -- UI Select (better code actions)
      {
        "nvim-telescope/telescope-ui-select.nvim",
      },

      -- File Browser (advanced file management)
      {
        "nvim-telescope/telescope-file-browser.nvim",
      },

      -- Project management
      {
        "nvim-telescope/telescope-project.nvim",
      },

      -- Smart file history (frecency = frequent + recent)
      {
        "nvim-telescope/telescope-frecency.nvim",
        dependencies = { "kkharji/sqlite.lua" },
      },
    },
    keys = {
      -- Core Telescope (already defined, but enhanced here)
      { "<leader>ff", "<cmd>Telescope find_files<cr>", desc = "Find Files" },
      {
        "<leader>fg",
        function()
          -- Try git_files first, fall back to find_files if not in git repo
          local ok = pcall(require("telescope.builtin").git_files, {})
          if not ok then
            require("telescope.builtin").find_files({})
          end
        end,
        desc = "Find Git Files (or Files)",
      },
      { "<leader>fr", "<cmd>Telescope oldfiles<cr>", desc = "Recent Files" },
      { "<leader>fb", "<cmd>Telescope buffers<cr>", desc = "Buffers" },
      { "<leader>fh", "<cmd>Telescope help_tags<cr>", desc = "Help Tags" },
      { "<leader>sg", "<cmd>Telescope live_grep<cr>", desc = "Live Grep" },
      { "<leader>sw", "<cmd>Telescope grep_string<cr>", desc = "Grep Word" },

      -- Extension: File Browser
      -- Note: <leader>e and <leader>fe are handled by LazyVim's snacks explorer
      { "<leader>e", false }, -- Disabled in favor of snacks explorer
      { "<leader>fe", false }, -- Disabled in favor of snacks explorer
      { "<leader>fE", "<cmd>Telescope file_browser path=%:p:h select_buffer=true<cr>", desc = "File Browser (cwd)" },

      -- Extension: Projects
      { "<leader>fp", "<cmd>Telescope project<cr>", desc = "Projects" },

      -- Extension: Frecency (smart history)
      { "<leader>fF", "<cmd>Telescope frecency<cr>", desc = "Frecency (Smart History)" },

      -- LSP with Telescope
      { "<leader>fs", "<cmd>Telescope lsp_document_symbols<cr>", desc = "Document Symbols" },
      { "<leader>fS", "<cmd>Telescope lsp_workspace_symbols<cr>", desc = "Workspace Symbols" },
      { "<leader>fd", "<cmd>Telescope diagnostics<cr>", desc = "Diagnostics" },

      -- Git with Telescope
      { "<leader>gc", "<cmd>Telescope git_commits<cr>", desc = "Git Commits" },
      { "<leader>gs", "<cmd>Telescope git_status<cr>", desc = "Git Status" },
      { "<leader>gb", "<cmd>Telescope git_branches<cr>", desc = "Git Branches" },

      -- Advanced searches
      { "<leader>fC", "<cmd>Telescope commands<cr>", desc = "Commands" },
      { "<leader>fk", "<cmd>Telescope keymaps<cr>", desc = "Keymaps" },
      { "<leader>fm", "<cmd>Telescope marks<cr>", desc = "Marks" },
      { "<leader>fj", "<cmd>Telescope jumplist<cr>", desc = "Jumplist" },
      { "<leader>fq", "<cmd>Telescope quickfix<cr>", desc = "Quickfix" },
      { "<leader>fl", "<cmd>Telescope loclist<cr>", desc = "Location List" },

      -- Resume last search
      { "<leader>f.", "<cmd>Telescope resume<cr>", desc = "Resume Last Search" },
    },
    config = function()
      local telescope = require("telescope")
      local actions = require("telescope.actions")
      local fb_actions = require("telescope").extensions.file_browser.actions

      telescope.setup({
        defaults = {
          -- Visual configuration
          prompt_prefix = "  ",
          selection_caret = " ",
          entry_prefix = "  ",
          multi_icon = " ",

          -- Border style
          borderchars = { "─", "│", "─", "│", "╭", "╮", "╯", "╰" },

          -- Layout configuration
          layout_strategy = "horizontal",
          layout_config = {
            horizontal = {
              prompt_position = "top",
              preview_width = 0.55,
              results_width = 0.8,
            },
            vertical = {
              mirror = false,
            },
            width = 0.87,
            height = 0.80,
            preview_cutoff = 120,
          },

          -- Sorting strategy (top or bottom)
          sorting_strategy = "ascending",

          -- Performance
          file_sorter = require("telescope.sorters").get_fuzzy_file,
          file_ignore_patterns = {
            "node_modules",
            ".git/",
            "%.lock",
            "target/",
            "build/",
            "dist/",
            "%.o",
            "%.a",
            "%.out",
            "%.class",
            "%.pdf",
            "%.mkv",
            "%.mp4",
            "%.zip",
          },

          -- Preview settings
          winblend = 0,
          color_devicons = true,
          set_env = { ["COLORTERM"] = "truecolor" },

          -- Mappings
          mappings = {
            i = {
              -- Navigation
              ["<C-n>"] = actions.cycle_history_next,
              ["<C-p>"] = actions.cycle_history_prev,
              ["<C-j>"] = actions.move_selection_next,
              ["<C-k>"] = actions.move_selection_previous,

              -- Close
              ["<C-c>"] = actions.close,
              ["<Esc>"] = actions.close,

              -- Scrolling
              ["<C-u>"] = actions.preview_scrolling_up,
              ["<C-d>"] = actions.preview_scrolling_down,

              -- Selection
              ["<CR>"] = actions.select_default,
              ["<C-x>"] = actions.select_horizontal,
              ["<C-v>"] = actions.select_vertical,
              ["<C-t>"] = actions.select_tab,

              -- Multi-selection
              ["<Tab>"] = actions.toggle_selection + actions.move_selection_worse,
              ["<S-Tab>"] = actions.toggle_selection + actions.move_selection_better,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,

              -- Other
              ["<C-l>"] = actions.complete_tag,
            },
            n = {
              ["<Esc>"] = actions.close,
              ["<CR>"] = actions.select_default,
              ["<C-x>"] = actions.select_horizontal,
              ["<C-v>"] = actions.select_vertical,
              ["<C-t>"] = actions.select_tab,

              ["<Tab>"] = actions.toggle_selection + actions.move_selection_worse,
              ["<S-Tab>"] = actions.toggle_selection + actions.move_selection_better,
              ["<C-q>"] = actions.send_to_qflist + actions.open_qflist,
              ["<M-q>"] = actions.send_selected_to_qflist + actions.open_qflist,

              ["j"] = actions.move_selection_next,
              ["k"] = actions.move_selection_previous,
              ["H"] = actions.move_to_top,
              ["M"] = actions.move_to_middle,
              ["L"] = actions.move_to_bottom,

              ["<Down>"] = actions.move_selection_next,
              ["<Up>"] = actions.move_selection_previous,
              ["gg"] = actions.move_to_top,
              ["G"] = actions.move_to_bottom,

              ["<C-u>"] = actions.preview_scrolling_up,
              ["<C-d>"] = actions.preview_scrolling_down,

              ["?"] = actions.which_key,
            },
          },
        },

        pickers = {
          -- Find files configuration
          find_files = {
            theme = "dropdown",
            previewer = false,
            hidden = true,
            find_command = { "rg", "--files", "--hidden", "--glob", "!.git/*" },
          },

          -- Git files
          git_files = {
            theme = "dropdown",
            previewer = false,
          },

          -- Buffers
          buffers = {
            theme = "dropdown",
            previewer = false,
            initial_mode = "normal",
            mappings = {
              i = {
                ["<C-d>"] = actions.delete_buffer,
              },
              n = {
                ["dd"] = actions.delete_buffer,
              },
            },
          },

          -- Live grep
          live_grep = {
            additional_args = function()
              return { "--hidden" }
            end,
          },

          -- LSP references
          lsp_references = {
            theme = "cursor",
            initial_mode = "normal",
          },

          -- LSP implementations
          lsp_implementations = {
            theme = "cursor",
            initial_mode = "normal",
          },

          -- LSP definitions
          lsp_definitions = {
            theme = "cursor",
            initial_mode = "normal",
          },
        },

        extensions = {
          -- FZF native (CRITICAL for performance)
          fzf = {
            fuzzy = true,
            override_generic_sorter = true,
            override_file_sorter = true,
            case_mode = "smart_case",
          },

          -- UI Select (better code actions)
          ["ui-select"] = {
            require("telescope.themes").get_dropdown({
              -- Specific settings
              previewer = false,
              initial_mode = "normal",
              sorting_strategy = "ascending",
              layout_strategy = "horizontal",
              layout_config = {
                horizontal = {
                  width = 0.5,
                  height = 0.4,
                  preview_width = 0.6,
                },
              },
            }),
          },

          -- File Browser
          file_browser = {
            theme = "ivy",
            hijack_netrw = false, -- Don't hijack netrw, let Neo-Tree handle it
            mappings = {
              ["i"] = {
                ["<C-w>"] = function() vim.cmd("normal vbd") end,
              },
              ["n"] = {
                ["N"] = fb_actions.create,
                ["h"] = fb_actions.goto_parent_dir,
                ["/"] = function() vim.cmd("startinsert") end,
                ["<C-u>"] = function(prompt_bufnr)
                  for i = 1, 10 do
                    actions.move_selection_previous(prompt_bufnr)
                  end
                end,
                ["<C-d>"] = function(prompt_bufnr)
                  for i = 1, 10 do
                    actions.move_selection_next(prompt_bufnr)
                  end
                end,
              },
            },
          },

          -- Project
          project = {
            base_dirs = {
              { path = "~/projects", max_depth = 2 },
              { path = "~/work", max_depth = 2 },
              { path = "~/.config", max_depth = 1 },
            },
            hidden_files = true,
            theme = "dropdown",
            order_by = "recent",
            search_by = "title",
            sync_with_nvim_tree = false,
          },

          -- Frecency (smart history)
          frecency = {
            show_scores = false,
            show_unindexed = true,
            ignore_patterns = { "*.git/*", "*/tmp/*", "*/node_modules/*" },
            disable_devicons = false,
            workspaces = {
              ["config"] = "~/.config",
              ["projects"] = "~/projects",
              ["work"] = "~/work",
            },
          },
        },
      })

      -- Load extensions
      telescope.load_extension("fzf")
      telescope.load_extension("ui-select")
      telescope.load_extension("file_browser")
      telescope.load_extension("project")

      -- Load frecency with error handling (can fail if database is corrupted)
      local ok, err = pcall(function()
        telescope.load_extension("frecency")
      end)
      if not ok then
        vim.notify("Frecency extension failed to load: " .. tostring(err), vim.log.levels.WARN)
        vim.notify("Run: rm ~/.local/state/nvim/file_frecency.bin", vim.log.levels.INFO)
      end

      -- Create autocmd to auto-detect projects
      vim.api.nvim_create_autocmd("VimEnter", {
        callback = function()
          -- Auto-detect git root as project
          if vim.fn.isdirectory(".git") == 1 then
            vim.notify("Project detected!", vim.log.levels.INFO)
          end
        end,
      })
    end,
  },

  -- Which-key integration
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>f", group = "find/file", icon = " " },
        { "<leader>ff", desc = "Find Files" },
        { "<leader>fg", desc = "Git Files" },
        { "<leader>fr", desc = "Recent Files" },
        { "<leader>fb", desc = "Buffers" },
        { "<leader>fh", desc = "Help Tags" },
        { "<leader>fe", desc = "File Browser" },
        { "<leader>fE", desc = "File Browser (cwd)" },
        { "<leader>fp", desc = "Projects" },
        { "<leader>fF", desc = "Frecency" },
        { "<leader>fs", desc = "Document Symbols" },
        { "<leader>fS", desc = "Workspace Symbols" },
        { "<leader>fd", desc = "Diagnostics" },
        { "<leader>fC", desc = "Commands" },
        { "<leader>fk", desc = "Keymaps" },
        { "<leader>fm", desc = "Marks" },
        { "<leader>fj", desc = "Jumplist" },
        { "<leader>fq", desc = "Quickfix" },
        { "<leader>fl", desc = "Location List" },
        { "<leader>f.", desc = "Resume Last" },
      },
    },
  },
}
