-- ═══════════════════════════════════════════════════════════
--                   DOCKER LSP CONFIGURATION
-- ═══════════════════════════════════════════════════════════
--
-- Advanced Docker LSP setup with custom keybindings
--
-- ═══════════════════════════════════════════════════════════

local M = {}

function M.setup()
  local lspconfig = require("lspconfig")

  -- Dockerfile LSP
  lspconfig.dockerls.setup({
    on_attach = function(client, bufnr)
      -- Enable completion triggered by <c-x><c-o>
      vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

      -- Buffer local mappings
      local opts = { buffer = bufnr, noremap = true, silent = true }

      -- Docker-specific keybindings
      vim.keymap.set("n", "<leader>Db", function()
        local file = vim.fn.expand("%:p")
        local tag = vim.fn.input("Docker tag: ", "myapp:latest")
        vim.cmd("terminal docker build -t " .. tag .. " -f " .. file .. " .")
      end, vim.tbl_extend("force", opts, { desc = "Docker: Build from Dockerfile" }))

      vim.keymap.set("n", "<leader>Dr", function()
        local tag = vim.fn.input("Docker image to run: ", "myapp:latest")
        vim.cmd("terminal docker run -it --rm " .. tag)
      end, vim.tbl_extend("force", opts, { desc = "Docker: Run container" }))

      vim.keymap.set("n", "<leader>Dl", function()
        vim.cmd("terminal docker ps -a")
      end, vim.tbl_extend("force", opts, { desc = "Docker: List containers" }))

      vim.keymap.set("n", "<leader>Di", function()
        vim.cmd("terminal docker images")
      end, vim.tbl_extend("force", opts, { desc = "Docker: List images" }))

      vim.keymap.set("n", "<leader>Dc", function()
        local container = vim.fn.input("Container ID/name: ")
        if container ~= "" then
          vim.cmd("terminal docker logs -f " .. container)
        end
      end, vim.tbl_extend("force", opts, { desc = "Docker: Container logs" }))

      vim.keymap.set("n", "<leader>De", function()
        local container = vim.fn.input("Container ID/name: ")
        if container ~= "" then
          vim.cmd("terminal docker exec -it " .. container .. " /bin/sh")
        end
      end, vim.tbl_extend("force", opts, { desc = "Docker: Exec into container" }))
    end,
    capabilities = require("cmp_nvim_lsp").default_capabilities(),
    settings = {
      docker = {
        languageserver = {
          formatter = {
            ignoreMultilineInstructions = true,
          },
        },
      },
    },
  })

  -- Docker Compose LSP
  lspconfig.docker_compose_language_service.setup({
    on_attach = function(client, bufnr)
      vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

      local opts = { buffer = bufnr, noremap = true, silent = true }

      -- Docker Compose specific keybindings
      vim.keymap.set("n", "<leader>Du", function()
        local file = vim.fn.expand("%:p")
        vim.cmd("terminal docker-compose -f " .. file .. " up")
      end, vim.tbl_extend("force", opts, { desc = "Docker Compose: Up" }))

      vim.keymap.set("n", "<leader>Dd", function()
        local file = vim.fn.expand("%:p")
        vim.cmd("terminal docker-compose -f " .. file .. " down")
      end, vim.tbl_extend("force", opts, { desc = "Docker Compose: Down" }))

      vim.keymap.set("n", "<leader>Ds", function()
        local file = vim.fn.expand("%:p")
        vim.cmd("terminal docker-compose -f " .. file .. " ps")
      end, vim.tbl_extend("force", opts, { desc = "Docker Compose: Status" }))

      vim.keymap.set("n", "<leader>DL", function()
        local file = vim.fn.expand("%:p")
        vim.cmd("terminal docker-compose -f " .. file .. " logs -f")
      end, vim.tbl_extend("force", opts, { desc = "Docker Compose: Logs" }))
    end,
    capabilities = require("cmp_nvim_lsp").default_capabilities(),
  })
end

return M
