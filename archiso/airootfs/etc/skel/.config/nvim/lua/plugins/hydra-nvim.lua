-- ═══════════════════════════════════════════════════════════
--           HYDRA - PERSISTENT MODE KEYBINDINGS
-- ═══════════════════════════════════════════════════════════
--
-- Create modal keybinding layers for repetitive tasks
--
-- Features:
--   - Window resize mode (h/j/k/l repeatedly)
--   - Git staging mode (stage/unstage multiple files)
--   - Option toggle mode (multiple settings at once)
--   - Scroll mode (navigate without holding keys)
--
-- ═══════════════════════════════════════════════════════════

return {
  "nvimtools/hydra.nvim",
  event = "VeryLazy",
  config = function()
    local Hydra = require("hydra")

    -- ══════════════════════════════════════════════════════
    -- WINDOW RESIZE HYDRA
    -- ══════════════════════════════════════════════════════
    Hydra({
      name = "Resize Windows",
      mode = "n",
      body = "<leader>w",
      hint = [[
 ↔ _h_/_l_: width │ ↕ _j_/_k_: height │ _=_: equalize │ _q_: quit
]],
      config = {
        invoke_on_body = false,
        hint = {
          position = "middle",
          float_opts = {
            border = "rounded",
          },
        },
      },
      heads = {
        { "h", "<C-w>3<", { desc = "Decrease width" } },
        { "l", "<C-w>3>", { desc = "Increase width" } },
        { "k", "<C-w>2+", { desc = "Increase height" } },
        { "j", "<C-w>2-", { desc = "Decrease height" } },
        { "=", "<C-w>=", { desc = "Equalize windows", exit = true } },
        { "q", nil, { exit = true, desc = "Quit" } },
        { "<Esc>", nil, { exit = true, desc = false } },
      },
    })

    -- ══════════════════════════════════════════════════════
    -- GIT STAGING HYDRA
    -- ══════════════════════════════════════════════════════
    Hydra({
      name = "Git Stage/Unstage",
      mode = "n",
      body = "<leader>gg",
      hint = [[
 _s_: stage hunk │ _u_: unstage hunk │ _S_: stage buffer │ _U_: reset buffer
 _n_: next hunk  │ _p_: prev hunk    │ _v_: view diff    │ _q_: quit
]],
      config = {
        invoke_on_body = false,
        color = "pink",
        hint = {
          position = "bottom",
          float_opts = {
            border = "rounded",
          },
        },
      },
      heads = {
        {
          "s",
          function()
            require("gitsigns").stage_hunk()
            vim.notify("Hunk staged", vim.log.levels.INFO)
          end,
          { desc = "Stage hunk" },
        },
        {
          "u",
          function()
            require("gitsigns").undo_stage_hunk()
            vim.notify("Hunk unstaged", vim.log.levels.INFO)
          end,
          { desc = "Unstage hunk" },
        },
        {
          "S",
          function()
            require("gitsigns").stage_buffer()
            vim.notify("Buffer staged", vim.log.levels.INFO)
          end,
          { desc = "Stage buffer" },
        },
        {
          "U",
          function()
            require("gitsigns").reset_buffer()
            vim.notify("Buffer reset", vim.log.levels.WARN)
          end,
          { desc = "Reset buffer" },
        },
        { "n", function() require("gitsigns").next_hunk() end, { desc = "Next hunk" } },
        { "p", function() require("gitsigns").prev_hunk() end, { desc = "Prev hunk" } },
        { "v", function() require("gitsigns").preview_hunk() end, { desc = "Preview hunk" } },
        { "q", nil, { exit = true, desc = "Quit" } },
        { "<Esc>", nil, { exit = true, desc = false } },
      },
    })

    -- ══════════════════════════════════════════════════════
    -- OPTIONS TOGGLE HYDRA
    -- ══════════════════════════════════════════════════════
    local hint = [[
 _n_: number          _r_: relative number  _w_: wrap
 _s_: spell           _c_: cursor line      _l_: list chars
 _h_: inlay hints     _d_: diagnostics      _C_: conceal level

 _q_: quit
]]

    Hydra({
      name = "Toggle Options",
      mode = "n",
      body = "<leader>ut",
      hint = hint,
      config = {
        invoke_on_body = false,
        color = "amaranth",
        hint = {
          position = "middle",
          float_opts = {
            border = "rounded",
          },
        },
      },
      heads = {
        {
          "n",
          function()
            vim.wo.number = not vim.wo.number
            vim.notify("Number: " .. tostring(vim.wo.number), vim.log.levels.INFO)
          end,
          { desc = "Number" },
        },
        {
          "r",
          function()
            vim.wo.relativenumber = not vim.wo.relativenumber
            vim.notify("Relative Number: " .. tostring(vim.wo.relativenumber), vim.log.levels.INFO)
          end,
          { desc = "Relative Number" },
        },
        {
          "w",
          function()
            vim.wo.wrap = not vim.wo.wrap
            vim.notify("Wrap: " .. tostring(vim.wo.wrap), vim.log.levels.INFO)
          end,
          { desc = "Wrap" },
        },
        {
          "s",
          function()
            vim.wo.spell = not vim.wo.spell
            vim.notify("Spell: " .. tostring(vim.wo.spell), vim.log.levels.INFO)
          end,
          { desc = "Spell" },
        },
        {
          "c",
          function()
            vim.wo.cursorline = not vim.wo.cursorline
            vim.notify("Cursor Line: " .. tostring(vim.wo.cursorline), vim.log.levels.INFO)
          end,
          { desc = "Cursor Line" },
        },
        {
          "l",
          function()
            vim.wo.list = not vim.wo.list
            vim.notify("List Chars: " .. tostring(vim.wo.list), vim.log.levels.INFO)
          end,
          { desc = "List Chars" },
        },
        {
          "h",
          function()
            if vim.lsp.inlay_hint then
              local enabled = vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
              vim.lsp.inlay_hint.enable(not enabled, { bufnr = 0 })
              vim.notify("Inlay Hints: " .. tostring(not enabled), vim.log.levels.INFO)
            end
          end,
          { desc = "Inlay Hints" },
        },
        {
          "d",
          function()
            vim.diagnostic.enable(not vim.diagnostic.is_enabled())
            vim.notify("Diagnostics: " .. tostring(vim.diagnostic.is_enabled()), vim.log.levels.INFO)
          end,
          { desc = "Diagnostics" },
        },
        {
          "C",
          function()
            vim.wo.conceallevel = vim.wo.conceallevel == 0 and 2 or 0
            vim.notify("Conceal Level: " .. vim.wo.conceallevel, vim.log.levels.INFO)
          end,
          { desc = "Conceal Level" },
        },
        { "q", nil, { exit = true, desc = "Quit" } },
        { "<Esc>", nil, { exit = true, desc = false } },
      },
    })

    -- ══════════════════════════════════════════════════════
    -- SCROLL/NAVIGATE HYDRA
    -- ══════════════════════════════════════════════════════
    Hydra({
      name = "Scroll/Navigate",
      mode = "n",
      body = "<leader>z",
      hint = [[
 _j_/_k_: scroll │ _d_/_u_: half page │ _f_/_b_: full page │ _q_: quit
]],
      config = {
        invoke_on_body = false,
        hint = {
          position = "middle",
          float_opts = {
            border = "rounded",
          },
        },
      },
      heads = {
        { "j", "3<C-e>3j", { desc = "Scroll down" } },
        { "k", "3<C-y>3k", { desc = "Scroll up" } },
        { "d", "<C-d>", { desc = "Half page down" } },
        { "u", "<C-u>", { desc = "Half page up" } },
        { "f", "<C-f>", { desc = "Full page down" } },
        { "b", "<C-b>", { desc = "Full page up" } },
        { "q", nil, { exit = true, desc = "Quit" } },
        { "<Esc>", nil, { exit = true, desc = false } },
      },
    })

    -- ══════════════════════════════════════════════════════
    -- BUFFER NAVIGATION HYDRA
    -- ══════════════════════════════════════════════════════
    Hydra({
      name = "Buffer Navigation",
      mode = "n",
      body = "<leader>b",
      hint = [[
 _n_: next buffer │ _p_: prev buffer │ _d_: delete buffer │ _q_: quit
]],
      config = {
        invoke_on_body = false,
        hint = {
          position = "middle",
          float_opts = {
            border = "rounded",
          },
        },
      },
      heads = {
        { "n", "<cmd>bnext<cr>", { desc = "Next buffer" } },
        { "p", "<cmd>bprevious<cr>", { desc = "Prev buffer" } },
        { "d", "<cmd>bdelete<cr>", { desc = "Delete buffer", exit = true } },
        { "q", nil, { exit = true, desc = "Quit" } },
        { "<Esc>", nil, { exit = true, desc = false } },
      },
    })
  end,
}
