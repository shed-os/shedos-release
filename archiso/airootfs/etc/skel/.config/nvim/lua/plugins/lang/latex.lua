-- LaTeX language plugin configuration
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, { "latex", "bibtex" })
    end,
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, {
        "texlab",
        "latexindent",
      })
    end,
  },

  {
    "lervag/vimtex",
    ft = { "tex", "latex" },
    config = function()
      vim.g.vimtex_view_method = "zathura" -- or "skim" on macOS
      vim.g.vimtex_compiler_method = "latexmk"
      vim.g.vimtex_quickfix_mode = 0
    end,
  },
}
