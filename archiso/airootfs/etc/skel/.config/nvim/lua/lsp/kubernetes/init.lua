-- ═══════════════════════════════════════════════════════════
--                 KUBERNETES LSP CONFIGURATION
-- ═══════════════════════════════════════════════════════════
--
-- Advanced Kubernetes and Helm LSP setup with kubectl integration
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Add kubectl keybindings to YAML buffers
local function setup_kubectl_keymaps(bufnr)
  local opts = { buffer = bufnr, noremap = true, silent = true }

  -- Kubernetes-specific keybindings
  vim.keymap.set("n", "<leader>Ka", function()
    local file = vim.fn.expand("%:p")
    vim.cmd("terminal kubectl apply -f " .. file)
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Apply manifest" }))

  vim.keymap.set("n", "<leader>Kd", function()
    local file = vim.fn.expand("%:p")
    vim.cmd("terminal kubectl delete -f " .. file)
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Delete manifest" }))

  vim.keymap.set("n", "<leader>Kv", function()
    local file = vim.fn.expand("%:p")
    vim.cmd("terminal kubectl apply --dry-run=client -f " .. file)
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Validate manifest" }))

  vim.keymap.set("n", "<leader>Kg", function()
    local resource_type = vim.fn.input("Resource type (pods/services/deployments): ", "pods")
    vim.cmd("terminal kubectl get " .. resource_type)
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Get resources" }))

  vim.keymap.set("n", "<leader>Kl", function()
    local pod = vim.fn.input("Pod name: ")
    if pod ~= "" then
      vim.cmd("terminal kubectl logs -f " .. pod)
    end
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Pod logs" }))

  vim.keymap.set("n", "<leader>Ke", function()
    local pod = vim.fn.input("Pod name: ")
    if pod ~= "" then
      local container = vim.fn.input("Container name (optional): ")
      local cmd = "kubectl exec -it " .. pod
      if container ~= "" then
        cmd = cmd .. " -c " .. container
      end
      cmd = cmd .. " -- /bin/sh"
      vim.cmd("terminal " .. cmd)
    end
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Exec into pod" }))

  vim.keymap.set("n", "<leader>Ks", function()
    local resource_type = vim.fn.input("Resource type: ", "pod")
    local resource_name = vim.fn.input("Resource name: ")
    if resource_name ~= "" then
      vim.cmd("terminal kubectl describe " .. resource_type .. " " .. resource_name)
    end
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Describe resource" }))

  vim.keymap.set("n", "<leader>Kp", function()
    local pod = vim.fn.input("Pod name: ")
    if pod ~= "" then
      local local_port = vim.fn.input("Local port: ", "8080")
      local pod_port = vim.fn.input("Pod port: ", "8080")
      vim.cmd("terminal kubectl port-forward " .. pod .. " " .. local_port .. ":" .. pod_port)
    end
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Port forward" }))

  vim.keymap.set("n", "<leader>Kn", function()
    vim.cmd("terminal kubectl get namespaces")
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: List namespaces" }))

  vim.keymap.set("n", "<leader>Kc", function()
    vim.cmd("terminal kubectl config get-contexts")
  end, vim.tbl_extend("force", opts, { desc = "Kubectl: Get contexts" }))
end

function M.setup()
  local lspconfig = require("lspconfig")
  local util = require("lspconfig.util")

  -- Add kubectl keybindings to YAML files
  vim.api.nvim_create_autocmd("FileType", {
    pattern = "yaml",
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      setup_kubectl_keymaps(bufnr)
    end,
  })

  -- Helm LSP (uses proper capabilities)
  lspconfig.helm_ls.setup({
    capabilities = require("lsp.utils").get_capabilities(),
    root_dir = function(fname)
      return util.root_pattern("Chart.yaml", ".git")(fname) or util.path.dirname(fname)
    end,
    on_attach = function(client, bufnr)
      local opts = { buffer = bufnr, noremap = true, silent = true }

      -- Helm-specific keybindings
      vim.keymap.set("n", "<leader>Kh", function()
        vim.cmd("terminal helm lint .")
      end, vim.tbl_extend("force", opts, { desc = "Helm: Lint chart" }))

      vim.keymap.set("n", "<leader>Kt", function()
        local release = vim.fn.input("Release name: ", "myapp")
        vim.cmd("terminal helm template " .. release .. " .")
      end, vim.tbl_extend("force", opts, { desc = "Helm: Template chart" }))

      vim.keymap.set("n", "<leader>Ki", function()
        local release = vim.fn.input("Release name: ", "myapp")
        local namespace = vim.fn.input("Namespace: ", "default")
        vim.cmd("terminal helm install " .. release .. " . -n " .. namespace)
      end, vim.tbl_extend("force", opts, { desc = "Helm: Install chart" }))
    end,
    settings = {
      ["helm-ls"] = {
        yamlls = {
          enabled = true,
        },
      },
    },
  })
end

-- Call setup immediately (not on FileType, since this handles both YAML keymaps and Helm LSP)
M.setup()

return M
