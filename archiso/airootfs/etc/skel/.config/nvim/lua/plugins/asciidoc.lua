-- Asciidoc language plugin configuration
return {
  { "nvim-treesitter/nvim-treesitter", opts = function(_, opts)
    vim.list_extend(opts.ensure_installed or {}, { "asciidoc" })
  end },
  
  { "habamax/vim-asciidoctor", ft = { "asciidoc", "asciidoctor" } },
}
