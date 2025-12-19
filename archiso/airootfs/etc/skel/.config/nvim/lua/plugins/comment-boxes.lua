-- ═══════════════════════════════════════════════════════════
--                  COMMENT BOX GENERATOR
-- ═══════════════════════════════════════════════════════════
--
-- Create beautiful comment boxes for code documentation
--
-- Perfect for:
--   - Section headers in large files
--   - Important TODOs and notes
--   - API endpoint documentation
--   - Visual code organization
--   - Professional code presentation
--
-- ═══════════════════════════════════════════════════════════

return {
  -- comment-box.nvim - Beautiful comment boxes
  {
    "LudoPinelli/comment-box.nvim",
    event = "VeryLazy",
    keys = {
      -- Box styles
      { "<leader>Cb", "<cmd>CBllbox<cr>", mode = { "n", "v" }, desc = "Box: Left-aligned box" },
      { "<leader>CB", "<cmd>CBcbox<cr>", mode = { "n", "v" }, desc = "Box: Centered box" },
      { "<leader>Cl", "<cmd>CBline<cr>", mode = { "n", "v" }, desc = "Box: Simple line" },
      { "<leader>CL", "<cmd>CBccbox<cr>", mode = { "n", "v" }, desc = "Box: Centered box (compact)" },

      -- Titled boxes
      { "<leader>Ct", "<cmd>CBllbox3<cr>", mode = { "n", "v" }, desc = "Box: Titled box" },
      { "<leader>CT", "<cmd>CBcbox3<cr>", mode = { "n", "v" }, desc = "Box: Centered titled box" },

      -- Adaptive boxes (language-aware)
      { "<leader>Ca", "<cmd>CBllbox1<cr>", mode = { "n", "v" }, desc = "Box: Adaptive box" },
      { "<leader>CA", "<cmd>CBcbox1<cr>", mode = { "n", "v" }, desc = "Box: Adaptive centered" },

      -- Remove box
      { "<leader>Cd", "<cmd>CBd<cr>", mode = { "n", "v" }, desc = "Box: Remove box" },

      -- Special boxes for common use cases
      { "<leader>Cc", "<cmd>CBllbox14<cr>", mode = { "n", "v" }, desc = "Box: Clean box" },
      { "<leader>Cs", "<cmd>CBllbox17<cr>", mode = { "n", "v" }, desc = "Box: Section header" },
      { "<leader>Cn", "<cmd>CBllbox11<cr>", mode = { "n", "v" }, desc = "Box: NOTE box" },
      { "<leader>Cw", "<cmd>CBllbox12<cr>", mode = { "n", "v" }, desc = "Box: WARNING box" },
    },
    config = function()
      require("comment-box").setup({
        -- Box style configuration
        doc_width = 80, -- width of the document
        box_width = 70, -- width of the boxes
        borders = {
          top = "─",
          bottom = "─",
          left = "│",
          right = "│",
          top_left = "╭",
          top_right = "╮",
          bottom_left = "╰",
          bottom_right = "╯",
        },
        line_width = 70,
        lines = {
          line = "─",
          line_start = "─",
          line_end = "─",
          title_left = "─",
          title_right = "─",
        },
        outer_blank_lines_above = 0,
        outer_blank_lines_below = 0,
        inner_blank_lines = 0,
        line_blank_lines_above = 0,
        line_blank_lines_below = 0,
      })

      -- Create custom box styles for different purposes

      -- Custom function: API Endpoint box
      vim.keymap.set({ "n", "v" }, "<leader>Ce", function()
        local line = vim.api.nvim_get_current_line()
        local box = {
          "-- " .. string.rep("═", 68),
          "--                        " .. line:gsub("^%s+", ""):gsub("%s+$", ""),
          "-- " .. string.rep("═", 68),
        }
        local row = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, box)
      end, { desc = "Box: API Endpoint Header" })

      -- Custom function: TODO box
      vim.keymap.set({ "n", "v" }, "<leader>Cx", function()
        local line = vim.api.nvim_get_current_line()
        local text = line:gsub("^%s+", ""):gsub("%s+$", "")
        local box = {
          "-- ┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓",
          "-- ┃  TODO: " .. text .. string.rep(" ", math.max(0, 58 - #text)) .. "┃",
          "-- ┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛",
        }
        local row = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, box)
      end, { desc = "Box: TODO Box" })

      -- Custom function: FIXME box
      vim.keymap.set({ "n", "v" }, "<leader>Cf", function()
        local line = vim.api.nvim_get_current_line()
        local text = line:gsub("^%s+", ""):gsub("%s+$", "")
        local box = {
          "-- ╔═══════════════════════════════════════════════════════════════╗",
          "-- ║  FIXME: " .. text .. string.rep(" ", math.max(0, 55 - #text)) .. "║",
          "-- ╚═══════════════════════════════════════════════════════════════╝",
        }
        local row = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, box)
      end, { desc = "Box: FIXME Box" })

      -- Custom function: Class/Interface header
      vim.keymap.set({ "n", "v" }, "<leader>Ci", function()
        local line = vim.api.nvim_get_current_line()
        local text = line:gsub("^%s+", ""):gsub("%s+$", "")
        local padding = math.max(0, 64 - #text)
        local left_pad = math.floor(padding / 2)
        local right_pad = padding - left_pad
        local box = {
          "/**",
          " * " .. string.rep("═", 66),
          " * " .. string.rep(" ", left_pad) .. text .. string.rep(" ", right_pad),
          " * " .. string.rep("═", 66),
          " */",
        }
        local row = vim.api.nvim_win_get_cursor(0)[1]
        vim.api.nvim_buf_set_lines(0, row - 1, row, false, box)
      end, { desc = "Box: Java/TypeScript Doc Header" })
    end,
  },

  -- Which-key integration
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>C", group = "comment-box", icon = " " },
        -- Basic boxes
        { "<leader>Cb", desc = "Box: Left-aligned" },
        { "<leader>CB", desc = "Box: Centered" },
        { "<leader>Cl", desc = "Box: Simple line" },
        { "<leader>CL", desc = "Box: Centered compact" },
        -- Titled boxes
        { "<leader>Ct", desc = "Box: Titled" },
        { "<leader>CT", desc = "Box: Centered titled" },
        -- Adaptive
        { "<leader>Ca", desc = "Box: Adaptive" },
        { "<leader>CA", desc = "Box: Adaptive centered" },
        -- Special
        { "<leader>Cc", desc = "Box: Clean" },
        { "<leader>Cs", desc = "Box: Section header" },
        { "<leader>Cn", desc = "Box: NOTE" },
        { "<leader>Cw", desc = "Box: WARNING" },
        { "<leader>Cd", desc = "Box: Remove" },
        -- Custom
        { "<leader>Ce", desc = "Box: API Endpoint" },
        { "<leader>Cx", desc = "Box: TODO" },
        { "<leader>Cf", desc = "Box: FIXME" },
        { "<leader>Ci", desc = "Box: Class/Interface" },
      },
    },
  },
}
