-- ═══════════════════════════════════════════════════════════
--                    ECLIPSE JDTLS CONFIGURATION
-- ═══════════════════════════════════════════════════════════
--
-- This is the core Java Language Server configuration.
-- Based on Eclipse JDT.LS with enhanced capabilities.
--
-- Features:
-- - Full LSP support (completion, diagnostics, hover, etc.)
-- - Advanced refactoring
-- - Code actions and quick fixes
-- - Organize imports
-- - Extract variable/method/constant
-- - Generate getters/setters/constructors
-- - Override/implement methods
-- - Spring Boot/Quarkus support
-- - Maven/Gradle integration
-- - JUnit/TestNG support
--
-- ═══════════════════════════════════════════════════════════

local M = {}

local paths = require("lsp.java.core.paths")

-- Extended capabilities for Java
function M.get_capabilities()
  -- Get base capabilities (compatible with blink.cmp or nvim-cmp)
  local capabilities = require("lsp.utils").get_capabilities()

  -- Enhanced completion capabilities
  capabilities.textDocument.completion.completionItem.snippetSupport = true
  capabilities.textDocument.completion.completionItem.resolveSupport = {
    properties = {
      "documentation",
      "detail",
      "additionalTextEdits",
    },
  }

  -- Code action literal support
  capabilities.textDocument.codeAction = {
    dynamicRegistration = false,
    codeActionLiteralSupport = {
      codeActionKind = {
        valueSet = {
          "",
          "quickfix",
          "refactor",
          "refactor.extract",
          "refactor.inline",
          "refactor.rewrite",
          "source",
          "source.organizeImports",
        },
      },
    },
  }

  -- Workspace edit support
  capabilities.workspace.applyEdit = true
  capabilities.workspace.workspaceEdit = {
    documentChanges = true,
    resourceOperations = { "create", "rename", "delete" },
  }

  return capabilities
end

-- Handlers for LSP events
function M.get_handlers()
  return {
    ["language/status"] = function(_, result)
      -- Handle language server status notifications
      -- Can be used to show compilation progress, etc.
    end,
    ["$/progress"] = function(_, result, ctx)
      -- Handle progress notifications from JDTLS
      -- Useful for showing build progress
    end,
  }
end

-- On attach callback for Java buffers
function M.on_attach(client, bufnr)
  -- Enable completion triggered by <c-x><c-o>
  vim.api.nvim_buf_set_option(bufnr, "omnifunc", "v:lua.vim.lsp.omnifunc")

  local opts = { buffer = bufnr, silent = true }

  -- ═══════════════════════════════════════════════════════
  --                    LSP KEYMAPS
  -- ═══════════════════════════════════════════════════════

  -- Navigation
  vim.keymap.set("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Go to definition" }))
  vim.keymap.set("n", "gD", vim.lsp.buf.declaration, vim.tbl_extend("force", opts, { desc = "Go to declaration" }))
  vim.keymap.set(
    "n",
    "gi",
    vim.lsp.buf.implementation,
    vim.tbl_extend("force", opts, { desc = "Go to implementation" })
  )
  vim.keymap.set("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "Show references" }))
  vim.keymap.set(
    "n",
    "gy",
    vim.lsp.buf.type_definition,
    vim.tbl_extend("force", opts, { desc = "Go to type definition" })
  )

  -- Documentation
  vim.keymap.set("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover documentation" }))
  vim.keymap.set("n", "<C-k>", vim.lsp.buf.signature_help, vim.tbl_extend("force", opts, { desc = "Signature help" }))
  vim.keymap.set("i", "<C-k>", vim.lsp.buf.signature_help, vim.tbl_extend("force", opts, { desc = "Signature help" }))

  -- Workspace
  vim.keymap.set(
    "n",
    "<leader>wa",
    vim.lsp.buf.add_workspace_folder,
    vim.tbl_extend("force", opts, { desc = "Add workspace folder" })
  )
  vim.keymap.set(
    "n",
    "<leader>wr",
    vim.lsp.buf.remove_workspace_folder,
    vim.tbl_extend("force", opts, { desc = "Remove workspace folder" })
  )
  vim.keymap.set("n", "<leader>wl", function()
    print(vim.inspect(vim.lsp.buf.list_workspace_folders()))
  end, vim.tbl_extend("force", opts, { desc = "List workspace folders" }))

  -- Code actions
  vim.keymap.set(
    { "n", "v" },
    "<leader>ca",
    vim.lsp.buf.code_action,
    vim.tbl_extend("force", opts, { desc = "Code action" })
  )
  vim.keymap.set("n", "<leader>cr", vim.lsp.buf.rename, vim.tbl_extend("force", opts, { desc = "Rename" }))

  -- Formatting
  vim.keymap.set("n", "<leader>cf", function()
    vim.lsp.buf.format({ async = true })
  end, vim.tbl_extend("force", opts, { desc = "Format buffer" }))

  -- ═══════════════════════════════════════════════════════
  --                    JAVA-SPECIFIC KEYMAPS
  -- ═══════════════════════════════════════════════════════

  local jdtls_ok, jdtls = pcall(require, "jdtls")
  if not jdtls_ok then
    vim.notify("nvim-jdtls not available for keymaps", vim.log.levels.WARN)
    return
  end

  -- Organize imports
  vim.keymap.set(
    "n",
    "<leader>jo",
    jdtls.organize_imports,
    vim.tbl_extend("force", opts, { desc = "Organize imports" })
  )

  -- Extract variable
  vim.keymap.set("v", "<leader>jv", function()
    jdtls.extract_variable()
  end, vim.tbl_extend("force", opts, { desc = "Extract variable" }))

  -- Extract constant
  vim.keymap.set("v", "<leader>jc", function()
    jdtls.extract_constant()
  end, vim.tbl_extend("force", opts, { desc = "Extract constant" }))

  -- Extract method
  vim.keymap.set("v", "<leader>jm", function()
    jdtls.extract_method()
  end, vim.tbl_extend("force", opts, { desc = "Extract method" }))

  -- Update project configuration
  vim.keymap.set(
    "n",
    "<leader>ju",
    jdtls.update_project_config,
    vim.tbl_extend("force", opts, { desc = "Update project config" })
  )

  -- ═══════════════════════════════════════════════════════
  --                    TESTING KEYMAPS
  -- ═══════════════════════════════════════════════════════

  -- Test class
  vim.keymap.set("n", "<leader>tc", function()
    jdtls.test_class()
  end, vim.tbl_extend("force", opts, { desc = "Test class" }))

  -- Test nearest method
  vim.keymap.set("n", "<leader>tm", function()
    jdtls.test_nearest_method()
  end, vim.tbl_extend("force", opts, { desc = "Test method" }))

  -- Pick test
  vim.keymap.set("n", "<leader>tp", function()
    jdtls.pick_test()
  end, vim.tbl_extend("force", opts, { desc = "Pick test" }))

  -- ═══════════════════════════════════════════════════════
  --                    DAP KEYMAPS
  -- ═══════════════════════════════════════════════════════

  -- Set up DAP for Java (with protection in case nvim-dap isn't loaded)
  pcall(function()
    jdtls.setup_dap({ hotcodereplace = "auto" })
  end)

  vim.keymap.set("n", "<leader>db", function()
    local dap_ok, dap = pcall(require, "dap")
    if dap_ok then dap.toggle_breakpoint() end
  end, vim.tbl_extend("force", opts, { desc = "Toggle breakpoint" }))

  vim.keymap.set("n", "<leader>dc", function()
    local dap_ok, dap = pcall(require, "dap")
    if dap_ok then dap.continue() end
  end, vim.tbl_extend("force", opts, { desc = "Continue" }))

  vim.keymap.set("n", "<leader>ds", function()
    local dap_ok, dap = pcall(require, "dap")
    if dap_ok then dap.step_over() end
  end, vim.tbl_extend("force", opts, { desc = "Step over" }))

  vim.keymap.set("n", "<leader>di", function()
    local dap_ok, dap = pcall(require, "dap")
    if dap_ok then dap.step_into() end
  end, vim.tbl_extend("force", opts, { desc = "Step into" }))

  vim.keymap.set("n", "<leader>do", function()
    local dap_ok, dap = pcall(require, "dap")
    if dap_ok then dap.step_out() end
  end, vim.tbl_extend("force", opts, { desc = "Step out" }))

  -- ═══════════════════════════════════════════════════════
  --                    COMPLETION SETUP
  -- ═══════════════════════════════════════════════════════

  -- Enable Java-specific completion features
  if client.server_capabilities.completionProvider then
    vim.bo[bufnr].omnifunc = "v:lua.vim.lsp.omnifunc"
  end

  -- ═══════════════════════════════════════════════════════
  --                    AUTOCOMMANDS
  -- ═══════════════════════════════════════════════════════

  -- Organize imports on save
  if vim.g.java_auto_organize_imports then
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = bufnr,
      callback = function()
        jdtls.organize_imports()
      end,
    })
  end

  -- Format on save
  if vim.g.java_format_on_save then
    vim.api.nvim_create_autocmd("BufWritePre", {
      buffer = bufnr,
      callback = function()
        vim.lsp.buf.format({ async = false })
      end,
    })
  end

  -- Show diagnostics in a floating window on cursor hold
  vim.api.nvim_create_autocmd("CursorHold", {
    buffer = bufnr,
    callback = function()
      vim.diagnostic.open_float(nil, {
        focusable = false,
        close_events = { "BufLeave", "CursorMoved", "InsertEnter", "FocusLost" },
        border = "rounded",
        source = "always",
        prefix = " ",
        scope = "cursor",
      })
    end,
  })

  vim.notify("JDTLS attached to buffer", vim.log.levels.INFO)
end

-- Get JDTLS settings
function M.get_settings()
  return {
    java = {
      -- Java runtime detection
      configuration = {
        updateBuildConfiguration = "automatic",
        runtimes = {
          {
            name = "JavaSE-25",
            path = paths.get_java_home(),
            default = true,
          },
          {
            name = "JavaSE-21",
            path = paths.get_java_home(),
          },
        },
      },

      -- Eclipse settings
      eclipse = {
        downloadSources = true,
      },

      -- Maven settings
      maven = {
        downloadSources = true,
        updateSnapshots = true,
      },

      -- References code lens
      referencesCodeLens = {
        enabled = true,
      },

      -- Implementation code lens
      implementationsCodeLens = {
        enabled = true,
      },

      -- Format settings
      format = {
        enabled = true,
        settings = {
          url = vim.fn.stdpath("config") .. "/java-format.xml",
          profile = "GoogleStyle",
        },
      },

      -- Completion settings
      completion = {
        favoriteStaticMembers = {
          "org.junit.jupiter.api.Assertions.*",
          "org.junit.Assert.*",
          "org.mockito.Mockito.*",
          "org.mockito.ArgumentMatchers.*",
          "org.mockito.Matchers.*",
        },
        filteredTypes = {
          "com.sun.*",
          "io.micrometer.shaded.*",
          "java.awt.*",
          "jdk.*",
          "sun.*",
        },
        importOrder = {
          "java",
          "javax",
          "org",
          "com",
        },
      },

      -- Sources settings
      sources = {
        organizeImports = {
          starThreshold = 9999,
          staticStarThreshold = 9999,
        },
      },

      -- Code generation settings
      codeGeneration = {
        toString = {
          template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
        },
        useBlocks = true,
        generateComments = true,
        hashCodeEquals = {
          useJava7Objects = true,
        },
      },

      -- Inlay hints (for Java 11+)
      inlayHints = {
        parameterNames = {
          enabled = "all",
        },
      },

      -- Signature help
      signatureHelp = {
        enabled = true,
        description = {
          enabled = true,
        },
      },

      -- Content provider
      contentProvider = {
        preferred = "fernflower",
      },

      -- Autobuild
      autobuild = {
        enabled = true,
      },

      -- Progress reports
      progressReports = {
        enabled = true,
      },

      -- ═══════════════════════════════════════════════════
      --                    FRAMEWORK SUPPORT
      -- ═══════════════════════════════════════════════════

      -- Spring Boot
      boot = {
        ls = {
          enabled = true,
        },
      },

      -- Quarkus
      quarkus = {
        tools = {
          enabled = true,
        },
      },
    },
  }
end

-- Initialize command for JDTLS
function M.get_init_options()
  return {
    bundles = paths.get_bundles(),
    extendedClientCapabilities = {
      progressReportProvider = true,
      classFileContentsSupport = true,
      generateToStringPromptSupport = true,
      hashCodeEqualsPromptSupport = true,
      advancedExtractRefactoringSupport = true,
      advancedOrganizeImportsSupport = true,
      generateConstructorsPromptSupport = true,
      generateDelegateMethodsPromptSupport = true,
      moveRefactoringSupport = true,
      overrideMethodsPromptSupport = true,
      inferSelectionSupport = { "extractMethod", "extractVariable", "extractConstant" },
    },
  }
end

-- Get JDTLS command
function M.get_cmd()
  local jdtls_path = paths.get_jdtls_path()
  local config_dir = paths.get_jdtls_config_dir()
  local workspace_dir = paths.get_workspace_dir()
  local lombok_path = paths.get_lombok_path()
  local java_home = paths.get_java_home()

  if not java_home then
    vim.notify("Java home not found. Please set JAVA_HOME.", vim.log.levels.ERROR)
    return nil
  end

  -- Construct the command
  local cmd = {
    java_home .. "/bin/java",

    -- JVM arguments
    "-Declipse.application=org.eclipse.jdt.ls.core.id1",
    "-Dosgi.bundles.defaultStartLevel=4",
    "-Declipse.product=org.eclipse.jdt.ls.core.product",
    "-Dlog.protocol=true",
    "-Dlog.level=ALL",
    "-Xmx1G",
    "-XX:+UseG1GC",
    "-XX:+UseStringDeduplication",

    -- Lombok support
    "--add-modules=ALL-SYSTEM",
    "--add-opens",
    "java.base/java.util=ALL-UNNAMED",
    "--add-opens",
    "java.base/java.lang=ALL-UNNAMED",
    "-javaagent:" .. lombok_path,

    -- JAR file
    "-jar",
    vim.fn.glob(jdtls_path .. "/plugins/org.eclipse.equinox.launcher_*.jar"),

    -- Platform configuration
    "-configuration",
    config_dir,

    -- Workspace
    "-data",
    workspace_dir,
  }

  return cmd
end

-- Root directory detection
function M.get_root_dir()
  local root_markers = {
    -- Git
    ".git",
    -- Maven
    "pom.xml",
    -- Gradle
    "build.gradle",
    "build.gradle.kts",
    "settings.gradle",
    "settings.gradle.kts",
    "gradlew",
    -- Eclipse
    ".project",
    -- IntelliJ
    ".idea",
    -- Generic
    "src",
  }

  -- Safely require jdtls.setup
  local ok, jdtls_setup = pcall(require, "jdtls.setup")
  if ok and jdtls_setup.find_root then
    local root_dir = jdtls_setup.find_root(root_markers)
    if root_dir then
      return root_dir
    end
  end

  -- Fallback to current working directory
  return vim.fn.getcwd()
end

-- Main setup function called from ftplugin/java.lua
function M.setup()
  -- Safely require jdtls (may not be loaded yet by Lazy.nvim)
  local ok, jdtls = pcall(require, "jdtls")
  if not ok then
    vim.notify("nvim-jdtls not loaded yet. Please wait for plugins to load.", vim.log.levels.WARN)
    return
  end

  -- Build config table with protected calls
  local cmd_ok, cmd = pcall(M.get_cmd)
  if not cmd_ok then
    vim.notify("Failed to get JDTLS command: " .. tostring(cmd), vim.log.levels.ERROR)
    return
  end

  local root_ok, root_dir = pcall(M.get_root_dir)
  if not root_ok then
    vim.notify("Failed to get root directory: " .. tostring(root_dir), vim.log.levels.ERROR)
    return
  end

  local cap_ok, capabilities = pcall(M.get_capabilities)
  if not cap_ok then
    vim.notify("Failed to get capabilities: " .. tostring(capabilities), vim.log.levels.ERROR)
    return
  end

  local config = {
    cmd = cmd,
    root_dir = root_dir,
    capabilities = capabilities,
    handlers = M.get_handlers(),
    on_attach = M.on_attach,
    settings = M.get_settings(),
    init_options = M.get_init_options(),

    -- Flags
    flags = {
      debounce_text_changes = 150,
      allow_incremental_sync = true,
    },
  }

  -- Start or attach JDTLS
  local attach_ok, attach_err = pcall(jdtls.start_or_attach, config)
  if not attach_ok then
    vim.notify("Failed to start JDTLS: " .. tostring(attach_err), vim.log.levels.ERROR)
  end
end

return M
