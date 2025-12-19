-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

local opt = vim.opt

-- Performance
opt.updatetime = 250 -- Faster completion (default 4000ms)
opt.timeoutlen = 300 -- Time to wait for mapped sequence
opt.ttimeoutlen = 10 -- Time to wait for key code sequence

-- UI
opt.number = true -- Show line numbers
opt.relativenumber = true -- Relative line numbers
opt.signcolumn = "yes" -- Always show sign column
opt.cursorline = true -- Highlight current line
opt.colorcolumn = "120" -- Show column at 120 chars
opt.pumheight = 15 -- Popup menu height
opt.pumblend = 10 -- Popup menu transparency
opt.winblend = 10 -- Floating window transparency
opt.showmode = false -- Don't show mode (we have statusline)
opt.showcmd = true -- Show command in statusline
opt.cmdheight = 1 -- Command line height
opt.laststatus = 3 -- Global statusline
opt.showtabline = 2 -- Always show tabline
opt.termguicolors = true -- True color support
opt.background = "dark" -- Dark theme preference

-- Editing
opt.tabstop = 4 -- Tab width
opt.shiftwidth = 4 -- Indent width
opt.softtabstop = 4 -- Tab key behavior
opt.expandtab = true -- Use spaces instead of tabs
opt.smartindent = true -- Smart auto-indenting
opt.autoindent = true -- Copy indent from current line
opt.breakindent = true -- Wrapped lines preserve indentation
opt.wrap = false -- Disable line wrapping
opt.linebreak = true -- Break lines at word boundaries
opt.scrolloff = 8 -- Keep 8 lines above/below cursor
opt.sidescrolloff = 8 -- Keep 8 columns left/right of cursor

-- Search
opt.ignorecase = true -- Case-insensitive search
opt.smartcase = true -- Case-sensitive if uppercase present
opt.hlsearch = true -- Highlight search results
opt.incsearch = true -- Incremental search

-- Completion
opt.completeopt = "menu,menuone,noselect" -- Completion menu behavior
opt.shortmess:append("c") -- Don't show completion messages

-- Files
opt.fileencoding = "utf-8" -- File encoding
opt.backup = false -- No backup files
opt.writebackup = false -- No backup before overwriting
opt.swapfile = false -- No swap files
opt.undofile = true -- Persistent undo
opt.undodir = vim.fn.stdpath("data") .. "/undo" -- Undo directory
opt.autowrite = true -- Auto-write on :make, :next, etc.
opt.autoread = true -- Auto-read file changes

-- Splits
opt.splitbelow = true -- Horizontal splits go below
opt.splitright = true -- Vertical splits go right
opt.splitkeep = "screen" -- Keep text on screen when splitting

-- Folds
opt.foldmethod = "expr" -- Use expression for folding
opt.foldexpr = "v:lua.vim.treesitter.foldexpr()" -- Use treesitter for folding
opt.foldlevel = 99 -- Open all folds by default
opt.foldlevelstart = 99 -- Open all folds when opening file
opt.foldenable = true -- Enable folding

-- Mouse
opt.mouse = "a" -- Enable mouse in all modes
opt.mousemoveevent = true -- Enable mouse move events

-- clipboard
opt.clipboard = "unnamedplus" -- Use system clipboard

-- Misc
opt.hidden = true -- Allow hidden buffers
opt.confirm = true -- Confirm before closing unsaved buffers
opt.spell = false -- Disable spell checking by default
opt.spelllang = "en_us" -- Spell check language
opt.conceallevel = 2 -- Conceal text when possible
opt.inccommand = "split" -- Show substitution preview
opt.virtualedit = "block" -- Allow cursor beyond end of line in visual block
opt.fillchars = {
  eob = " ", -- Remove ~ from empty lines
  fold = " ", -- Fold line fill character
  foldopen = "▾", -- Open fold indicator
  foldsep = " ", -- Fold separator
  foldclose = "▸", -- Closed fold indicator
  diff = "╱", -- Diff mode fill character
}
opt.listchars = {
  tab = "→ ",
  trail = "·",
  extends = "»",
  precedes = "«",
  nbsp = "␣",
}
opt.list = true -- Show whitespace characters

-- Diagnostics
vim.diagnostic.config({
  virtual_text = {
    prefix = "●",
    source = "if_many",
  },
  signs = true,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
  float = {
    source = "always",
    border = "rounded",
    focusable = false,
    header = "",
    prefix = "",
  },
})

-- Diagnostic signs
local signs = {
  Error = " ",
  Warn = " ",
  Hint = " ",
  Info = " ",
}

for type, icon in pairs(signs) do
  local hl = "DiagnosticSign" .. type
  vim.fn.sign_define(hl, { text = icon, texthl = hl, numhl = hl })
end

-- Disable some built-in plugins we don't need
local disabled_built_ins = {
  "2html_plugin",
  "getscript",
  "getscriptPlugin",
  "gzip",
  "logipat",
  "matchit",
  "tar",
  "tarPlugin",
  "rrhelper",
  "spellfile_plugin",
  "vimball",
  "vimballPlugin",
  "zip",
  "zipPlugin",
  "tutor",
  "rplugin",
  "syntax",
  "synmenu",
  "optwin",
  "compiler",
  "bugreport",
  "ftplugin",
}

for _, plugin in pairs(disabled_built_ins) do
  vim.g["loaded_" .. plugin] = 1
end

-- Fix markdown indentation settings
vim.g.markdown_recommended_style = 0

-- Java-specific globals
vim.g.java_format_on_save = true
vim.g.java_auto_organize_imports = true
vim.g.lombok_support = 1
