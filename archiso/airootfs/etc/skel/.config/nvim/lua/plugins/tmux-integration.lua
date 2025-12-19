-- ═══════════════════════════════════════════════════════════
--                    TMUX INTEGRATION
-- ═══════════════════════════════════════════════════════════
--
-- Seamless navigation between Neovim and Tmux panes
-- Essential for daily Tmux users!
--
-- Features:
--   - Navigate between nvim splits and tmux panes with same keys
--   - Send commands to tmux panes
--   - Resize nvim/tmux panes uniformly
--   - Integration with Tmux statusline
--
-- ═══════════════════════════════════════════════════════════

return {
  -- Seamless navigation between tmux and neovim
  {
    "christoomey/vim-tmux-navigator",
    cmd = {
      "TmuxNavigateLeft",
      "TmuxNavigateDown",
      "TmuxNavigateUp",
      "TmuxNavigateRight",
      "TmuxNavigatePrevious",
    },
    keys = {
      { "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "Navigate Left (Tmux)" },
      { "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "Navigate Down (Tmux)" },
      { "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "Navigate Up (Tmux)" },
      { "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "Navigate Right (Tmux)" },
      { "<C-\\>", "<cmd>TmuxNavigatePrevious<cr>", desc = "Navigate Previous (Tmux)" },
    },
    init = function()
      -- Disable tmux navigator when zooming the Vim pane
      vim.g.tmux_navigator_disable_when_zoomed = 1

      -- Save all buffers on switch
      vim.g.tmux_navigator_save_on_switch = 2

      -- Preserve zoom when switching panes
      vim.g.tmux_navigator_preserve_zoom = 1

      -- Don't wrap around when at edge
      vim.g.tmux_navigator_no_wrap = 0
    end,
  },

  -- Send commands to tmux panes
  {
    "preservim/vimux",
    cmd = {
      "VimuxRunCommand",
      "VimuxPromptCommand",
      "VimuxRunLastCommand",
      "VimuxCloseRunner",
      "VimuxInspectRunner",
      "VimuxZoomRunner",
      "VimuxInterruptRunner",
      "VimuxClearTerminalScreen",
      "VimuxTogglePane",
    },
    keys = {
      -- Run commands in tmux pane
      { "<leader>vp", "<cmd>VimuxPromptCommand<cr>", desc = "Tmux: Prompt Command" },
      { "<leader>vl", "<cmd>VimuxRunLastCommand<cr>", desc = "Tmux: Run Last Command" },
      { "<leader>vi", "<cmd>VimuxInspectRunner<cr>", desc = "Tmux: Inspect Runner" },
      { "<leader>vz", "<cmd>VimuxZoomRunner<cr>", desc = "Tmux: Zoom Runner" },
      { "<leader>vx", "<cmd>VimuxInterruptRunner<cr>", desc = "Tmux: Interrupt Runner" },
      { "<leader>vc", "<cmd>VimuxClearTerminalScreen<cr>", desc = "Tmux: Clear Screen" },
      { "<leader>vq", "<cmd>VimuxCloseRunner<cr>", desc = "Tmux: Close Runner" },
      { "<leader>vt", "<cmd>VimuxTogglePane<cr>", desc = "Tmux: Toggle Pane" },

      -- Language-specific runners
      {
        "<leader>vr",
        function()
          local ft = vim.bo.filetype
          local file = vim.fn.expand("%:p")
          local cmd = ""

          if ft == "python" then
            cmd = "python " .. file
          elseif ft == "javascript" or ft == "typescript" then
            cmd = "node " .. file
          elseif ft == "java" then
            cmd = "javac " .. file .. " && java " .. vim.fn.expand("%:t:r")
          elseif ft == "kotlin" then
            cmd = "kotlinc " .. file .. " -include-runtime -d output.jar && java -jar output.jar"
          elseif ft == "c" then
            cmd = "gcc " .. file .. " -o output && ./output"
          elseif ft == "cpp" then
            cmd = "g++ " .. file .. " -o output && ./output"
          elseif ft == "rust" then
            cmd = "cargo run"
          elseif ft == "go" then
            cmd = "go run " .. file
          elseif ft == "sh" or ft == "bash" then
            cmd = "bash " .. file
          else
            cmd = vim.fn.input("Command to run: ")
          end

          if cmd ~= "" then
            vim.cmd("VimuxRunCommand '" .. cmd .. "'")
          end
        end,
        desc = "Tmux: Run Current File",
      },

      -- Send visual selection to tmux
      {
        "<leader>vs",
        function()
          vim.cmd('normal! gv"vy')
          local selection = vim.fn.getreg("v")
          vim.cmd("VimuxRunCommand '" .. selection .. "'")
        end,
        mode = "v",
        desc = "Tmux: Send Selection",
      },
    },
    init = function()
      -- Height of the runner pane (percentage)
      vim.g.VimuxHeight = "30"

      -- Orientation of the runner pane (v = vertical, h = horizontal)
      vim.g.VimuxOrientation = "v"

      -- Use existing pane (not used by vim) if found instead of running split-window
      vim.g.VimuxUseNearest = 1

      -- Reset the sequence number when a new runner is created
      vim.g.VimuxResetSequence = ""

      -- Prompt string to use for VimuxPromptCommand
      vim.g.VimuxPromptString = "Command? "

      -- Run commands without pressing enter
      vim.g.VimuxRunnerType = "pane"
    end,
  },

  -- Tmux integration for Neovim statusline
  {
    "vimpostor/vim-tpipeline",
    enabled = function()
      -- Only enable if inside tmux
      return vim.env.TMUX ~= nil
    end,
    init = function()
      vim.g.tpipeline_statusline = ""
      vim.g.tpipeline_autoembed = 0
      vim.g.tpipeline_fillcentre = 1
      vim.g.tpipeline_focuslost = 1
      vim.g.tpipeline_cursormoved = 1
      vim.g.tpipeline_restore = 1
    end,
  },

  -- Which-key integration for Tmux commands
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>v", group = "tmux/vimux", icon = " " },
      },
    },
  },

  -- Add tmux.conf syntax highlighting
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      -- tmux syntax support via bash parser
      vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
        pattern = { ".tmux.conf", "tmux.conf" },
        callback = function()
          vim.bo.filetype = "tmux"
        end,
      })
    end,
  },
}
