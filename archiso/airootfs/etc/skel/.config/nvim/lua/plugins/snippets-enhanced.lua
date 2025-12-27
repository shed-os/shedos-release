-- ═══════════════════════════════════════════════════════════
--              ENHANCED SNIPPET SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- Massive snippet collection + custom snippets for your languages
-- Focus: Java, C/C++, Kotlin, TypeScript, JavaScript
--
-- ═══════════════════════════════════════════════════════════

return {
  -- LuaSnip - snippet engine
  {
    "L3MON4D3/LuaSnip",
    build = "make install_jsregexp", -- Optional: for advanced regex features
    dependencies = {
      "rafamadriz/friendly-snippets", -- Huge collection of snippets
      "saadparwaiz1/cmp_luasnip", -- LuaSnip completion source
    },
    opts = {
      history = true,
      delete_check_events = "TextChanged",
      updateevents = "TextChanged,TextChangedI",
    },
    config = function(_, opts)
      local luasnip = require("luasnip")
      luasnip.setup(opts)

      -- Load friendly-snippets (massive collection for all languages)
      require("luasnip.loaders.from_vscode").lazy_load()

      -- Load custom snippets from ~/.config/nvim/snippets/
      require("luasnip.loaders.from_lua").lazy_load({
        paths = vim.fn.stdpath("config") .. "/snippets",
      })

      -- Extended snippet configuration
      luasnip.config.set_config({
        -- Enable autotriggered snippets
        enable_autosnippets = true,

        -- Use Tab to trigger visual selection
        store_selection_keys = "<Tab>",

        -- Update more often for dynamic snippets
        update_events = "TextChanged,TextChangedI",
      })

      -- Filetype Extensions
      -- Allow specific filetypes to use snippets from other "snippet filetypes"
      luasnip.filetype_extend("java", { "spring-boot", "junit-mockito" })
      luasnip.filetype_extend("typescript", { "express-nestjs" })
      luasnip.filetype_extend("typescriptreact", { "express-nestjs" })
      luasnip.filetype_extend("javascript", { "express-nestjs" }) -- Experimental


      -- ═══════════════════════════════════════════════════════════
      -- KEYBINDINGS
      -- ═══════════════════════════════════════════════════════════

      vim.keymap.set({ "i", "s" }, "<C-k>", function()
        if luasnip.expand_or_jumpable() then
          luasnip.expand_or_jump()
        end
      end, { silent = true, desc = "Snippet: Expand or Jump Forward" })

      vim.keymap.set({ "i", "s" }, "<C-j>", function()
        if luasnip.jumpable(-1) then
          luasnip.jump(-1)
        end
      end, { silent = true, desc = "Snippet: Jump Backward" })

      vim.keymap.set({ "i", "s" }, "<C-l>", function()
        if luasnip.choice_active() then
          luasnip.change_choice(1)
        end
      end, { silent = true, desc = "Snippet: Change Choice" })

      -- List available snippets
      vim.keymap.set("n", "<leader>cs", function()
        require("luasnip.loaders").edit_snippet_files()
      end, { desc = "Code: Edit Snippets" })
    end,
  },

  -- nvim-cmp integration
  {
    "hrsh7th/nvim-cmp",
    optional = true,
    dependencies = {
      "saadparwaiz1/cmp_luasnip",
    },
    opts = function(_, opts)
      local cmp = require("cmp")
      local luasnip = require("luasnip")

      -- Add luasnip to sources
      opts.sources = opts.sources or {}
      table.insert(opts.sources, {
        name = "luasnip",
        priority = 750,
        keyword_length = 2,
        max_item_count = 10,
      })

      -- Enhanced snippet mapping
      local has_words_before = function()
        unpack = unpack or table.unpack
        local line, col = unpack(vim.api.nvim_win_get_cursor(0))
        return col ~= 0 and vim.api.nvim_buf_get_lines(0, line - 1, line, true)[1]:sub(col, col):match("%s") == nil
      end

      opts.mapping = vim.tbl_extend("force", opts.mapping or {}, {
        ["<Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_next_item()
          elseif luasnip.expand_or_locally_jumpable() then
            luasnip.expand_or_jump()
          elseif has_words_before() then
            cmp.complete()
          else
            fallback()
          end
        end, { "i", "s" }),

        ["<S-Tab>"] = cmp.mapping(function(fallback)
          if cmp.visible() then
            cmp.select_prev_item()
          elseif luasnip.jumpable(-1) then
            luasnip.jump(-1)
          else
            fallback()
          end
        end, { "i", "s" }),
      })

      return opts
    end,
  },
}
