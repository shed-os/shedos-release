-- Markdown language plugin configuration
return {
  { "nvim-treesitter/nvim-treesitter", opts = function(_, opts)
    vim.list_extend(opts.ensure_installed or {}, { "markdown", "markdown_inline" })
  end },
  
  { "mason-org/mason.nvim", opts = function(_, opts)
    vim.list_extend(opts.ensure_installed or {}, {
      "marksman", "markdownlint", "prettier",
    })
  end },
  
  { "iamcco/markdown-preview.nvim", ft = "markdown",
    build = "cd app && npm install",
    config = function()
      vim.g.mkdp_auto_start = 0
      vim.g.mkdp_auto_close = 1
    end,
  },
  
  { "MeanderingProgrammer/render-markdown.nvim", ft = "markdown",
    dependencies = { "nvim-treesitter/nvim-treesitter", "nvim-tree/nvim-web-devicons" },
    opts = {},
  },
}
