-- Java filetype settings

-- Set local options first
vim.opt_local.shiftwidth = 4
vim.opt_local.tabstop = 4
vim.opt_local.expandtab = true
vim.opt_local.colorcolumn = "120"

-- Setup JDTLS
require("lsp.java.core.jdtls").setup()

-- Add buffer-local keybindings after JDTLS setup
vim.schedule(function()
  local opts = { buffer = 0, silent = true }
  vim.keymap.set("n", "<leader>jr", function()
    -- Get the current file path and name without extension
    local file = vim.fn.expand("%:p")
    local file_no_ext = vim.fn.expand("%:p:r")
    local class_name = vim.fn.expand("%:t:r")

    -- Compile and run
    local cmd = string.format("cd %s && javac %s && java %s",
      vim.fn.expand("%:p:h"),
      vim.fn.expand("%:t"),
      class_name)

    vim.cmd("!" .. cmd)
  end, vim.tbl_extend("force", opts, { desc = "Java: Compile and Run" }))

  -- ═══════════════════════════════════════════════════════════
  -- JPA BUDDY++ KEYMAPS (for @Entity classes)
  -- ═══════════════════════════════════════════════════════════

  -- Check if this is a JPA entity
  local ok_parser, parser = pcall(require, "lsp.java.features.jpa.parser")
  if ok_parser and parser.is_jpa_entity(0) then
    -- SQL Generation
    vim.keymap.set("n", "<leader>js", "<cmd>JPAGenerateSQL<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate SQL DDL",
    }))
    vim.keymap.set("n", "<leader>jS", "<cmd>JPAGenerateProjectSQL<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate SQL for all entities",
    }))

    -- Code Generation
    vim.keymap.set("n", "<leader>jr", "<cmd>JPAGenerateRepository<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate Repository",
    }))
    vim.keymap.set("n", "<leader>jd", "<cmd>JPAGenerateDTO<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate DTO",
    }))
    vim.keymap.set("n", "<leader>jc", "<cmd>JPAGenerateController<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate REST Controller",
    }))

    -- Migrations
    vim.keymap.set("n", "<leader>jf", "<cmd>JPAGenerateFlywayMigration<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate Flyway Migration",
    }))
    vim.keymap.set("n", "<leader>jl", "<cmd>JPAGenerateLiquibaseMigration<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate Liquibase Migration",
    }))

    -- Documentation
    vim.keymap.set("n", "<leader>jD", "<cmd>JPAGenerateERD<cr>", vim.tbl_extend("force", opts, {
      desc = "JPA: Generate ERD",
    }))

    -- Show which-key group label
    local ok_wk, wk = pcall(require, "which-key")
    if ok_wk and wk then
      wk.add({
        { "<leader>j", group = "JPA", buffer = 0 },
      })
    end

    -- Show JPA detection notification
    vim.notify("✓ JPA Entity detected - JPA Buddy++ features enabled", vim.log.levels.INFO, { title = "JPA Buddy++" })
  end
end)
