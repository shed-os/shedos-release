-- ═══════════════════════════════════════════════════════════
--                   PERFORMANCE OPTIMIZATION
-- ═══════════════════════════════════════════════════════════
--
-- Optimize Neovim for fast startup and smooth performance
-- Target: < 100ms startup with 110+ plugins
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Disable providers we don't need
M.disable_providers = function()
  -- Disable Node.js provider (unless you use Node-based plugins)
  vim.g.loaded_node_provider = 0

  -- Disable Perl provider
  vim.g.loaded_perl_provider = 0

  -- Disable Ruby provider
  vim.g.loaded_ruby_provider = 0

  -- Python provider - keep enabled for potential plugins
  -- Uncomment to disable if you don't use Python plugins:
  -- vim.g.loaded_python3_provider = 0
end

-- Optimize filetype detection
M.optimize_filetype = function()
  -- Use Lua-based filetype detection (faster)
  vim.g.do_filetype_lua = 1
  vim.g.did_load_filetypes = 0
end

-- Optimize timing settings
M.optimize_timing = function()
  -- Faster completion popup
  vim.opt.updatetime = 250

  -- Faster which-key popup
  vim.opt.timeoutlen = 300

  -- Faster key code detection
  vim.opt.ttimeoutlen = 10

  -- Debounce for autocommands
  vim.opt.redrawtime = 1500
end

-- Optimize file handling
M.optimize_files = function()
  -- Disable swap files (we have undo persistence)
  vim.opt.swapfile = false

  -- Disable backup files
  vim.opt.backup = false
  vim.opt.writebackup = false

  -- Enable persistent undo
  vim.opt.undofile = true
  vim.opt.undolevels = 10000

  -- Set undo directory
  local undo_dir = vim.fn.stdpath("cache") .. "/undo"
  if vim.fn.isdirectory(undo_dir) == 0 then
    vim.fn.mkdir(undo_dir, "p")
  end
  vim.opt.undodir = undo_dir
end

-- Optimize UI rendering
M.optimize_ui = function()
  -- Don't redraw during macros, registers, and other operations
  vim.opt.lazyredraw = false -- Note: true can cause issues with some plugins

  -- Faster scrolling
  vim.opt.ttyfast = true

  -- Syntax highlighting max column
  vim.opt.synmaxcol = 240

  -- Better scroll behavior
  vim.opt.scrolloff = 8
  vim.opt.sidescrolloff = 8

  -- Optimize cursor hold
  vim.opt.cursorline = true
  vim.opt.cursorlineopt = "number" -- Only highlight line number, not whole line

  -- Faster macro execution
  vim.opt.regexpengine = 0 -- Auto-select the fastest engine
end

-- Optimize search
M.optimize_search = function()
  -- Incremental search
  vim.opt.incsearch = true

  -- Highlight search results
  vim.opt.hlsearch = true

  -- Smart case searching
  vim.opt.ignorecase = true
  vim.opt.smartcase = true

  -- Live substitution preview
  vim.opt.inccommand = "split"
end

-- Optimize completion
M.optimize_completion = function()
  -- Completion options
  vim.opt.completeopt = { "menu", "menuone", "noselect" }

  -- Faster completion
  vim.opt.pumheight = 10 -- Limit popup menu height
  vim.opt.pumblend = 10 -- Slight transparency

  -- Complete from all buffers
  vim.opt.complete = ".,w,b,u"
end

-- Optimize splits and windows
M.optimize_windows = function()
  -- Better split behavior
  vim.opt.splitbelow = true
  vim.opt.splitright = true

  -- Minimum window sizes
  vim.opt.winminheight = 1
  vim.opt.winminwidth = 5

  -- Equal window sizes
  vim.opt.equalalways = false
end

-- Optimize performance for large files
M.optimize_large_files = function()
  -- Create autocommand group
  local group = vim.api.nvim_create_augroup("LargeFileOptimization", { clear = true })

  -- Disable features for large files (>1MB)
  vim.api.nvim_create_autocmd("BufReadPre", {
    group = group,
    callback = function(args)
      local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(args.buf))
      if ok and stats then
        local max_filesize = 1024 * 1024 -- 1 MB
        if stats.size > max_filesize then
          -- Disable expensive features
          vim.bo[args.buf].swapfile = false
          vim.bo[args.buf].undofile = false
          vim.bo[args.buf].syntax = "off"

          -- Notify user
          vim.notify(
            string.format(
              "Large file detected (%s MB). Some features disabled for performance.",
              math.floor(stats.size / 1024 / 1024)
            ),
            vim.log.levels.WARN
          )
        end
      end
    end,
  })
end

-- Optimize LSP performance
M.optimize_lsp = function()
  -- Configure diagnostics (modern API)
  vim.diagnostic.config({
    -- Don't update diagnostics in insert mode
    update_in_insert = false,

    -- Virtual text settings
    virtual_text = {
      spacing = 4,
      prefix = "●",
      severity = { min = vim.diagnostic.severity.WARN },
    },

    -- Sign settings
    signs = true,

    -- Underline errors
    underline = true,

    -- Sort by severity
    severity_sort = true,
  })

  -- Optimize hover
  vim.lsp.handlers["textDocument/hover"] = vim.lsp.with(vim.lsp.handlers.hover, {
    border = "rounded",
    max_width = 80,
    max_height = 30,
  })

  -- Optimize signature help
  vim.lsp.handlers["textDocument/signatureHelp"] = vim.lsp.with(vim.lsp.handlers.signature_help, {
    border = "rounded",
    max_width = 80,
    max_height = 30,
  })
end

-- Optimize Treesitter performance
M.optimize_treesitter = function()
  -- This will be called after treesitter loads
  vim.defer_fn(function()
    if pcall(require, "nvim-treesitter.configs") then
      require("nvim-treesitter.configs").setup({
        highlight = {
          enable = true,
          -- Disable for large files
          disable = function(lang, buf)
            local max_filesize = 100 * 1024 -- 100 KB
            local ok, stats = pcall(vim.loop.fs_stat, vim.api.nvim_buf_get_name(buf))
            if ok and stats and stats.size > max_filesize then
              return true
            end
          end,

          -- Additional optimization
          additional_vim_regex_highlighting = false,
        },
      })
    end
  end, 100)
end

-- Memory optimization
M.optimize_memory = function()
  -- Set maximum memory for patterns
  vim.opt.maxmempattern = 2000

  -- History size
  vim.opt.history = 1000

  -- Maximum items in quickfix/location list
  vim.opt.jumpoptions = "stack"
end

-- Optimize clipboard
M.optimize_clipboard = function()
  -- Use system clipboard (but don't slow down startup)
  vim.schedule(function()
    vim.opt.clipboard = "unnamedplus"
  end)
end

-- Run all optimizations
M.setup = function()
  -- Core optimizations
  M.disable_providers()
  M.optimize_filetype()
  M.optimize_timing()
  M.optimize_files()

  -- UI optimizations
  M.optimize_ui()
  M.optimize_search()
  M.optimize_completion()
  M.optimize_windows()

  -- Feature optimizations
  M.optimize_large_files()
  M.optimize_lsp()
  M.optimize_memory()
  M.optimize_clipboard()

  -- Treesitter (deferred)
  M.optimize_treesitter()

  -- Notify user
  vim.defer_fn(function()
    -- Check if we want to show startup stats
    local show_stats = os.getenv("NVIM_SHOW_STATS")
    if show_stats then
      local stats = require("lazy").stats()
      vim.notify(
        string.format(
          "⚡ Neovim loaded %d/%d plugins in %.2fms",
          stats.loaded,
          stats.count,
          stats.startuptime
        ),
        vim.log.levels.INFO
      )
    end
  end, 200)
end

-- Performance monitoring command
vim.api.nvim_create_user_command("PerfStats", function()
  local stats = require("lazy").stats()
  local lines = {
    "📊 Performance Statistics",
    "",
    string.format("Plugins loaded: %d/%d", stats.loaded, stats.count),
    string.format("Startup time: %.2fms", stats.startuptime),
    "",
    "Memory usage:",
    string.format("  Lua: %.2f MB", collectgarbage("count") / 1024),
    "",
    "To profile startup:",
    "  :StartupTime",
    "  or",
    "  nvim --startuptime startup.log +qall",
  }

  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO)
end, { desc = "Show performance statistics" })

return M
