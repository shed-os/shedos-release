-- YAML Language Server Configuration
local M = {}

function M.setup()
    local lspconfig = require("lspconfig")
    local util = require("lspconfig.util")

    lspconfig.yamlls.setup({
        capabilities = require("lsp.utils").get_capabilities(),
        -- Explicitly set root directory to prevent null URI errors
        root_dir = function(fname)
            return util.root_pattern(
                ".git",
                "package.json",
                ".gitlab-ci.yml",
                ".github/workflows",
                "docker-compose.yml",
                "Dockerfile"
            )(fname) or util.path.dirname(fname)
        end,
        settings = {
            yaml = {
                hover = true,
                completion = true,
                validate = true,
                schemaStore = {
                    enable = true,
                    url = "https://www.schemastore.org/api/json/catalog.json",
                },
                schemas = {
                    kubernetes = "*.yaml",
                    ["http://json.schemastore.org/github-workflow"] = ".github/workflows/*",
                    ["http://json.schemastore.org/github-action"] = ".github/action.{yml,yaml}",
                    ["http://json.schemastore.org/ansible-stable-2.9"] = "roles/tasks/*.{yml,yaml}",
                    ["http://json.schemastore.org/prettierrc"] = ".prettierrc.{yml,yaml}",
                    ["http://json.schemastore.org/kustomization"] = "kustomization.{yml,yaml}",
                    ["http://json.schemastore.org/ansible-playbook"] = "*play*.{yml,yaml}",
                    ["http://json.schemastore.org/chart"] = "Chart.{yml,yaml}",
                    ["https://json.schemastore.org/dependabot-v2"] = ".github/dependabot.{yml,yaml}",
                    ["https://json.schemastore.org/gitlab-ci"] = "*gitlab-ci*.{yml,yaml}",
                    ["https://raw.githubusercontent.com/OAI/OpenAPI-Specification/main/schemas/v3.1/schema.json"] = "*api*.{yml,yaml}",
                    ["https://raw.githubusercontent.com/compose-spec/compose-spec/master/schema/compose-spec.json"] = "*docker-compose*.{yml,yaml}",
                    ["https://raw.githubusercontent.com/argoproj/argo-workflows/master/api/jsonschema/schema.json"] = "*flow*.{yml,yaml}",
                },
                format = {
                    enable = true,
                },
                customTags = {
                    "!Base64 scalar",
                    "!Cidr scalar",
                    "!And sequence",
                    "!Equals sequence",
                    "!If sequence",
                    "!Not sequence",
                    "!Or sequence",
                    "!Condition scalar",
                    "!FindInMap sequence",
                    "!GetAtt scalar",
                    "!GetAtt sequence",
                    "!GetAZs scalar",
                    "!ImportValue scalar",
                    "!Join sequence",
                    "!Select sequence",
                    "!Split sequence",
                    "!Sub scalar",
                    "!Sub sequence",
                    "!Ref scalar",
                },
            },
        },
    })
end

M.setup()
return M
