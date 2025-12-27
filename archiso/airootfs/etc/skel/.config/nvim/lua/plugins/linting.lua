return {
  {
    "mfussenegger/nvim-lint",
    event = { "BufReadPost", "BufWritePost", "BufEnter" },
    config = function()
      local lint = require("lint")

      lint.linters_by_ft = {
        ansible = { "ansible_lint" },
        bash = { "shellcheck" },
        sh = { "shellcheck" },
        cmake = { "cmakelint" },
        c = { "cpplint" },
        cpp = { "cpplint" },
        dockerfile = { "hadolint" },
        gitcommit = { "commitlint" },
        go = { "golangci_lint" },
        html = { "htmlhint" },
        css = { "stylelint" },
        scss = { "stylelint" },
        json = { "jsonlint" },
        java = { "checkstyle" },
        javascript = { "eslint_d" },
        typescript = { "eslint_d" },
        javascriptreact = { "eslint_d" },
        typescriptreact = { "eslint_d" },
        kotlin = { "ktlint" },
        markdown = { "markdownlint" },
        python = { "ruff", "flake8" },
        sql = { "sqlfluff" },
        terraform = { "tflint" },
        yaml = { "yamllint" },
      }

      -- Custom Configurations using ~/.config/nvim/ dotfiles

      -- Custom Configurations using ~/.config/nvim/ dotfiles

      -- cpplint
      local cpplint = lint.linters.cpplint
      if cpplint then
        cpplint.args = {
          "--reference_files",
          "--config=" .. vim.fn.expand("~/.config/nvim/CPPLINT.cfg"),
        }
      end

      -- golangci-lint (Note: key is usually golangcilint or golangci_lint)
      -- We check both to be safe
      local golangci = lint.linters.golangcilint or lint.linters.golangci_lint
      if golangci then
        golangci.args = {
          "run",
          "--out-format",
          "json",
          "--config=" .. vim.fn.expand("~/.config/nvim/.golangci.yml"),
        }
      end

      -- sqlfluff
      local sqlfluff = lint.linters.sqlfluff
      if sqlfluff then
        sqlfluff.args = {
          "lint",
          "--format=json",
          "--config=" .. vim.fn.expand("~/.config/nvim/.sqlfluff"),
        }
      end

      -- checkstyle
      local checkstyle = lint.linters.checkstyle
      if checkstyle then
        checkstyle.args = {
          "-c",
          vim.fn.expand("~/.config/nvim/checkstyle.xml"),
        }
      end

      -- stylelint
      local stylelint = lint.linters.stylelint
      if stylelint then
        stylelint.args = {
          "--formatter",
          "json",
          "--stdin-filename",
          "%filepath",
          "--config",
          vim.fn.expand("~/.config/nvim/.stylelintrc.json"),
        }
      end

      -- flake8
      local flake8 = lint.linters.flake8
      if flake8 then
        flake8.args = {
          "--format=%(path)s:%(row)d:%(col)d:%(code)s:%(text)s",
          "--no-show-source",
          "--stdin-display-name",
          "%(filepath)s",
          "--config=" .. vim.fn.expand("~/.config/nvim/.flake8"),
          "-",
        }
      end
      -- eslint_d
      local eslint = lint.linters.eslint_d
      if eslint then
        eslint.args = {
          "--no-warn-ignored", -- Suppress "File ignored..." warning
          "--format",
          "json",
          "--stdin",
          "--stdin-filename",
          "%filepath",
          "--config",
          vim.fn.expand("~/.config/nvim/.eslintrc.json"),
        }
      end

      -- Auto-trigger linting
      -- Auto-trigger linting
      vim.api.nvim_create_autocmd({ "BufEnter", "BufWritePost", "InsertLeave" }, {
        group = vim.api.nvim_create_augroup("nvim-lint", { clear = true }),
        callback = function()
          lint.try_lint()
        end,
      })
    end,
  },
}
