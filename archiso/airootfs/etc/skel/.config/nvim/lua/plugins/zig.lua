-- Zig language plugin configuration
return {
  {
    "nvim-treesitter/nvim-treesitter",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, { "zig" })
    end,
  },

  {
    "mason-org/mason.nvim",
    opts = function(_, opts)
      vim.list_extend(opts.ensure_installed or {}, { "zls" })
    end,
  },

  { "ziglang/zig.vim", ft = "zig" },
}
