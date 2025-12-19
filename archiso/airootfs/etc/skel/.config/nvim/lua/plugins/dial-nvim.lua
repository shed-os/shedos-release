-- ═══════════════════════════════════════════════════════════
--            DIAL - SMART INCREMENT/DECREMENT
-- ═══════════════════════════════════════════════════════════
--
-- Enhanced <C-a>/<C-x> for incrementing/decrementing
--
-- Features:
--   - Dates (2025-01-15 → 2025-01-16)
--   - Days (Monday → Tuesday)
--   - Booleans (true ↔ false)
--   - Hex colors (#ff0000 → #ff0001)
--   - Semantic versions (v1.2.3 → v1.2.4)
--   - Custom patterns per language
--
-- ═══════════════════════════════════════════════════════════

return {
  "monaqa/dial.nvim",
  keys = {
    {
      "<C-a>",
      function()
        require("dial.map").manipulate("increment", "normal")
      end,
      desc = "Increment",
    },
    {
      "<C-x>",
      function()
        require("dial.map").manipulate("decrement", "normal")
      end,
      desc = "Decrement",
    },
    {
      "g<C-a>",
      function()
        require("dial.map").manipulate("increment", "gnormal")
      end,
      desc = "Increment (gnormal)",
    },
    {
      "g<C-x>",
      function()
        require("dial.map").manipulate("decrement", "gnormal")
      end,
      desc = "Decrement (gnormal)",
    },
    {
      "<C-a>",
      function()
        require("dial.map").manipulate("increment", "visual")
      end,
      mode = "v",
      desc = "Increment",
    },
    {
      "<C-x>",
      function()
        require("dial.map").manipulate("decrement", "visual")
      end,
      mode = "v",
      desc = "Decrement",
    },
    {
      "g<C-a>",
      function()
        require("dial.map").manipulate("increment", "gvisual")
      end,
      mode = "v",
      desc = "Increment (gvisual)",
    },
    {
      "g<C-x>",
      function()
        require("dial.map").manipulate("decrement", "gvisual")
      end,
      mode = "v",
      desc = "Decrement (gvisual)",
    },
  },
  config = function()
    local augend = require("dial.augend")

    -- Configure default augends (increment/decrement rules)
    require("dial.config").augends:register_group({
      default = {
        -- Numbers (decimal)
        augend.integer.alias.decimal,
        -- Numbers (hex)
        augend.integer.alias.hex,
        -- Dates (YYYY-MM-DD, YYYY/MM/DD, DD.MM.YYYY)
        augend.date.alias["%Y-%m-%d"],
        augend.date.alias["%Y/%m/%d"],
        augend.date.alias["%d.%m.%Y"],
        augend.date.alias["%m/%d/%Y"],
        -- Days of the week
        augend.constant.alias.bool,
        augend.constant.new({
          elements = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "sunday" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" },
          word = true,
          cyclic = true,
        }),
        -- Months
        augend.constant.new({
          elements = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" },
          word = true,
          cyclic = true,
        }),
        -- Booleans
        augend.constant.new({
          elements = { "true", "false" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "True", "False" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "yes", "no" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "Yes", "No" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "on", "off" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "On", "Off" },
          word = true,
          cyclic = true,
        }),
        -- Logic operators
        augend.constant.new({
          elements = { "&&", "||" },
          word = false,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "and", "or" },
          word = true,
          cyclic = true,
        }),
        -- Comparison operators
        augend.constant.new({
          elements = { "==", "!=" },
          word = false,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "===", "!==" },
          word = false,
          cyclic = true,
        }),
        -- Hex colors (#RRGGBB)
        augend.hexcolor.new({
          case = "lower",
        }),
        -- Semantic versioning (v1.2.3)
        augend.semver.alias.semver,
      },

      -- TypeScript/JavaScript specific
      typescript = {
        augend.integer.alias.decimal,
        augend.integer.alias.hex,
        augend.constant.new({ elements = { "let", "const" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "true", "false" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "null", "undefined" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "public", "private", "protected" }, word = true, cyclic = true }),
        augend.hexcolor.new({ case = "lower" }),
      },

      -- Python specific
      python = {
        augend.integer.alias.decimal,
        augend.integer.alias.hex,
        augend.constant.new({ elements = { "True", "False" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "None" }, word = true, cyclic = false }),
        augend.constant.new({ elements = { "and", "or" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "import", "from" }, word = true, cyclic = true }),
      },

      -- Lua specific
      lua = {
        augend.integer.alias.decimal,
        augend.integer.alias.hex,
        augend.constant.new({ elements = { "true", "false" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "and", "or" }, word = true, cyclic = true }),
        augend.constant.new({ elements = { "local", "global" }, word = true, cyclic = true }),
      },

      -- Markdown specific
      markdown = {
        augend.integer.alias.decimal,
        augend.date.alias["%Y-%m-%d"],
        augend.constant.new({
          elements = { "TODO", "DONE", "WIP", "FIXME", "NOTE" },
          word = true,
          cyclic = true,
        }),
        augend.constant.new({
          elements = { "[ ]", "[x]" },
          word = false,
          cyclic = true,
        }),
      },
    })

    -- Setup filetype-specific augends
    vim.api.nvim_create_autocmd("FileType", {
      pattern = { "typescript", "typescriptreact", "javascript", "javascriptreact" },
      callback = function()
        vim.api.nvim_buf_set_var(0, "dial_augend_group", "typescript")
      end,
    })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "python",
      callback = function()
        vim.api.nvim_buf_set_var(0, "dial_augend_group", "python")
      end,
    })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "lua",
      callback = function()
        vim.api.nvim_buf_set_var(0, "dial_augend_group", "lua")
      end,
    })

    vim.api.nvim_create_autocmd("FileType", {
      pattern = "markdown",
      callback = function()
        vim.api.nvim_buf_set_var(0, "dial_augend_group", "markdown")
      end,
    })
  end,
}
