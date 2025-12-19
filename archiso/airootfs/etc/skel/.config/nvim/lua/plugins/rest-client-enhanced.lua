-- ═══════════════════════════════════════════════════════════
--              ENHANCED REST CLIENT FOR BACKEND WORK
-- ═══════════════════════════════════════════════════════════
--
-- Premium REST API testing directly from Neovim
-- Perfect for backend engineers who "breathe APIs"
--
-- File format: .http or .rest files
-- Example:
--   GET https://api.example.com/users
--   Authorization: Bearer {{token}}
--
-- ═══════════════════════════════════════════════════════════

return {
  -- Kulala.nvim - Modern REST client
  {
    "mistweaverco/kulala.nvim",
    ft = { "http", "rest" },
    keys = {
      -- Execute requests
      { "<leader>rr", "<cmd>lua require('kulala').run()<cr>", desc = "REST: Run Request" },
      { "<leader>ra", "<cmd>lua require('kulala').run_all()<cr>", desc = "REST: Run All Requests" },
      { "<leader>rR", "<cmd>lua require('kulala').replay()<cr>", desc = "REST: Replay Last Request" },

      -- Navigation
      { "<leader>rn", "<cmd>lua require('kulala').jump_next()<cr>", desc = "REST: Next Request" },
      { "<leader>rp", "<cmd>lua require('kulala').jump_prev()<cr>", desc = "REST: Previous Request" },

      -- View management
      { "<leader>rv", "<cmd>lua require('kulala').toggle_view()<cr>", desc = "REST: Toggle View" },
      { "<leader>ri", "<cmd>lua require('kulala').inspect()<cr>", desc = "REST: Inspect Request" },
      { "<leader>rh", "<cmd>lua require('kulala').show_stats()<cr>", desc = "REST: Show Stats" },

      -- Copy utilities
      { "<leader>rc", "<cmd>lua require('kulala').copy()<cr>", desc = "REST: Copy as cURL" },

      -- Environment management
      { "<leader>re", "<cmd>lua require('kulala').set_selected_env()<cr>", desc = "REST: Select Environment" },
      { "<leader>rE", "<cmd>lua require('kulala').show_env()<cr>", desc = "REST: Show Environment" },

      -- Search
      { "<leader>rs", "<cmd>lua require('kulala').search()<cr>", desc = "REST: Search Requests" },

      -- Scratchpad (quick testing)
      { "<leader>rt", "<cmd>lua require('kulala').scratchpad()<cr>", desc = "REST: Open Scratchpad" },
    },
    config = function()
      require("kulala").setup({
        -- Default request view (body, headers, headers_body, script_output)
        default_view = "body",

        -- Default environment (dev, staging, prod)
        default_env = "dev",

        -- Debug mode
        debug = false,

        -- Additional cURL options
        additional_curl_options = {},

        -- Format response body
        formatters = {
          json = { "jq", "." },
          xml = { "xmllint", "--format", "-" },
          html = { "prettier", "--parser", "html" },
        },

        -- Icons for request methods
        icons = {
          inlay = {
            loading = "⏳",
            done = "✅",
            error = "❌",
          },
          lualine = "🐼",
        },

        -- Split direction for response
        split_direction = "vertical",

        -- Default headers
        default_headers = {
          ["Content-Type"] = "application/json",
          ["User-Agent"] = "Kulala.nvim/1.0",
        },

        -- Disable SSL verification (useful for local/dev APIs)
        -- WARNING: Only use in development!
        -- disable_ssl_verification = true,

        -- Scratchpad default content
        scratchpad_default_contents = {
          "@baseUrl = http://localhost:8080",
          "",
          "### Quick test request",
          "GET {{baseUrl}}/api/health",
          "Accept: application/json",
          "",
          "###",
        },

        -- Environment files locations
        env_dir = vim.fn.stdpath("config") .. "/http-envs",

        -- Display mode (split, float)
        display_mode = "split",

        -- Winbar display
        winbar = true,

        -- Show icons in winbar
        show_icons = "on_request",

        -- vhosts
        vhosts = {},
      })

      -- Auto-completion for http files
      vim.api.nvim_create_autocmd("FileType", {
        pattern = { "http", "rest" },
        callback = function()
          -- Enable snippet-like completion for common HTTP methods and headers
          vim.bo.commentstring = "# %s"

          -- Set up better syntax highlighting
          vim.cmd([[
            syntax match httpVerb "\v(GET|POST|PUT|PATCH|DELETE|HEAD|OPTIONS|TRACE|CONNECT)"
            syntax match httpHeader "\v^\w+(-\w+)*:"
            syntax match httpVariable "\v\{\{[^}]+\}\}"

            highlight link httpVerb Keyword
            highlight link httpHeader Type
            highlight link httpVariable Identifier
          ]])
        end,
      })

      -- Create http-envs directory if it doesn't exist
      local env_dir = vim.fn.stdpath("config") .. "/http-envs"
      if vim.fn.isdirectory(env_dir) == 0 then
        vim.fn.mkdir(env_dir, "p")
      end

      -- Create sample environment files if they don't exist
      local function create_sample_env(name, content)
        local file_path = env_dir .. "/" .. name .. ".json"
        if vim.fn.filereadable(file_path) == 0 then
          local file = io.open(file_path, "w")
          if file then
            file:write(vim.fn.json_encode(content))
            file:close()
          end
        end
      end

      -- Sample environments for backend development
      create_sample_env("dev", {
        baseUrl = "http://localhost:8080",
        apiUrl = "http://localhost:8080/api",
        token = "dev-token-here",
        username = "dev-user",
        password = "dev-password",
      })

      create_sample_env("staging", {
        baseUrl = "https://staging.example.com",
        apiUrl = "https://staging.example.com/api",
        token = "staging-token-here",
        username = "staging-user",
        password = "staging-password",
      })

      create_sample_env("prod", {
        baseUrl = "https://api.example.com",
        apiUrl = "https://api.example.com/api",
        token = "prod-token-here",
        username = "prod-user",
        password = "prod-password",
      })
    end,
  },

  -- HTTP syntax highlighting enhancement
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      opts.ensure_installed = opts.ensure_installed or {}
      vim.list_extend(opts.ensure_installed, {
        "http",
        "json",
      })
    end,
  },

  -- Which-key integration for REST commands
  {
    "folke/which-key.nvim",
    optional = true,
    opts = {
      spec = {
        { "<leader>r", group = "refactor/rest", icon = " " },
      },
    },
  },
}
