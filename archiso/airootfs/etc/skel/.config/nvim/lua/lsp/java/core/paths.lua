-- ═══════════════════════════════════════════════════════════
--                    JAVA PATHS & WORKSPACE
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Get OS-specific path separator
M.path_separator = vim.fn.has("win32") == 1 and "\\" or "/"

-- Java home detection
function M.get_java_home()
  -- Try JAVA_HOME environment variable first
  local java_home = os.getenv("JAVA_HOME")
  if java_home and vim.fn.isdirectory(java_home) == 1 then
    return java_home
  end

  -- Try to find Java executable
  local java_exe = vim.fn.exepath("java")
  if java_exe ~= "" then
    -- Go up from bin/java to get JAVA_HOME
    java_home = vim.fn.fnamemodify(java_exe, ":p:h:h")
    if vim.fn.isdirectory(java_home) == 1 then
      return java_home
    end
  end

  -- Try common installation paths
  local common_paths = {
    "/home/theshedman/.local/share/mise/installs/java/openjdk-25.0.0/bin",
    "/home/theshedman/.local/share/mise/installs/java/openjdk-21.0.2/bin",
    "/home/theshedman/.local/share/mise/installs/java/openjdk-17.0.2/bin",
    "/usr/bin",
  }

  for _, path in ipairs(common_paths) do
    if vim.fn.isdirectory(path) == 1 then
      return path
    end
  end

  vim.notify("JAVA_HOME not found. Please set JAVA_HOME environment variable.", vim.log.levels.WARN)
  return nil
end

-- JDTLS installation path (via Mason)
function M.get_jdtls_path()
  -- Try Mason registry first
  local has_registry, mason_registry = pcall(require, "mason-registry")

  if has_registry then
    -- Check if jdtls is installed
    local is_installed = pcall(function()
      return mason_registry.is_installed("jdtls")
    end)

    if is_installed then
      -- Try to get the package
      local ok, jdtls_package = pcall(function()
        return mason_registry.get_package("jdtls")
      end)

      if ok and jdtls_package then
        -- Try to get install path
        local path_ok, path = pcall(function()
          return jdtls_package:get_install_path()
        end)

        if path_ok and path and vim.fn.isdirectory(path) == 1 then
          return path
        end
      end
    end
  end

  -- Fallback: Direct path check
  local fallback_path = vim.fn.expand("~/.local/share/nvim/mason/packages/jdtls")
  if vim.fn.isdirectory(fallback_path) == 1 then
    return fallback_path
  end

  -- Alternative Mason path (for some installations)
  local alt_path = vim.fn.stdpath("data") .. "/mason/packages/jdtls"
  if vim.fn.isdirectory(alt_path) == 1 then
    return alt_path
  end

  return nil
end

-- Lombok JAR path (via Mason)
function M.get_lombok_path()
  local jdtls_path = M.get_jdtls_path()
  if not jdtls_path then
    return nil
  end

  local lombok = jdtls_path .. "/lombok.jar"
  if vim.fn.filereadable(lombok) == 1 then
    return lombok
  end

  return nil
end

-- Java debug adapter path (via Mason)
function M.get_java_debug_adapter_path()
  -- Try Mason registry first
  local has_registry, mason_registry = pcall(require, "mason-registry")

  if has_registry then
    -- Check if java-debug-adapter is installed
    local is_installed = pcall(function()
      return mason_registry.is_installed("java-debug-adapter")
    end)

    if is_installed then
      -- Try to get the package
      local ok, package = pcall(function()
        return mason_registry.get_package("java-debug-adapter")
      end)

      if ok and package then
        -- Try to get install path
        local path_ok, path = pcall(function()
          return package:get_install_path()
        end)

        if path_ok and path and vim.fn.isdirectory(path) == 1 then
          return path
        end
      end
    end
  end

  -- Fallback: Direct path check
  local fallback_path = vim.fn.expand("~/.local/share/nvim/mason/packages/java-debug-adapter")
  if vim.fn.isdirectory(fallback_path) == 1 then
    return fallback_path
  end

  -- Alternative Mason path
  local alt_path = vim.fn.stdpath("data") .. "/mason/packages/java-debug-adapter"
  if vim.fn.isdirectory(alt_path) == 1 then
    return alt_path
  end

  return nil
end

-- Java test adapter path (via Mason)
function M.get_java_test_adapter_path()
  -- Try Mason registry first
  local has_registry, mason_registry = pcall(require, "mason-registry")

  if has_registry then
    -- Check if java-test is installed
    local is_installed = pcall(function()
      return mason_registry.is_installed("java-test")
    end)

    if is_installed then
      -- Try to get the package
      local ok, package = pcall(function()
        return mason_registry.get_package("java-test")
      end)

      if ok and package then
        -- Try to get install path
        local path_ok, path = pcall(function()
          return package:get_install_path()
        end)

        if path_ok and path and vim.fn.isdirectory(path) == 1 then
          return path
        end
      end
    end
  end

  -- Fallback: Direct path check
  local fallback_path = vim.fn.expand("~/.local/share/nvim/mason/packages/java-test")
  if vim.fn.isdirectory(fallback_path) == 1 then
    return fallback_path
  end

  -- Alternative Mason path
  local alt_path = vim.fn.stdpath("data") .. "/mason/packages/java-test"
  if vim.fn.isdirectory(alt_path) == 1 then
    return alt_path
  end

  return nil
end

-- Get workspace directory for current project
function M.get_workspace_dir()
  -- Use project root as workspace name
  local root_dir = require("jdtls.setup").find_root({ ".git", "mvnw", "gradlew", "pom.xml", "build.gradle" })
  if not root_dir then
    root_dir = vim.fn.getcwd()
  end

  -- Create workspace directory
  local workspace_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
  local workspace_dir = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. workspace_name

  -- Ensure workspace directory exists
  vim.fn.mkdir(workspace_dir, "p")

  return workspace_dir
end

-- Get OS-specific configuration directory for JDTLS
function M.get_jdtls_config_dir()
  local jdtls_path = M.get_jdtls_path()
  if not jdtls_path then
    return nil
  end

  local os_config = "config_linux"

  if vim.fn.has("mac") == 1 then
    os_config = "config_mac"
  elseif vim.fn.has("win32") == 1 then
    os_config = "config_win"
  end

  local config_dir = jdtls_path .. "/" .. os_config
  if vim.fn.isdirectory(config_dir) == 1 then
    return config_dir
  end

  return nil
end

-- Get bundles for debug adapter and test runner
function M.get_bundles()
  local bundles = {}

  -- Java debug adapter
  local java_debug_path = M.get_java_debug_adapter_path()
  if java_debug_path then
    local debug_bundle = vim.fn.glob(java_debug_path .. "/extension/server/com.microsoft.java.debug.plugin-*.jar", true)
    if debug_bundle and debug_bundle ~= "" then
      table.insert(bundles, debug_bundle)
    end
  end

  -- Java test runner
  local java_test_path = M.get_java_test_adapter_path()
  if java_test_path then
    local test_bundles = vim.split(vim.fn.glob(java_test_path .. "/extension/server/*.jar", true), "\n")
    for _, bundle in ipairs(test_bundles) do
      if bundle and bundle ~= "" then
        table.insert(bundles, bundle)
      end
    end
  end

  return bundles
end

-- Detect project type
function M.detect_project_type()
  local root_dir = vim.fn.getcwd()

  if vim.fn.filereadable(root_dir .. "/pom.xml") == 1 then
    return "maven"
  elseif
    vim.fn.filereadable(root_dir .. "/build.gradle") == 1
    or vim.fn.filereadable(root_dir .. "/build.gradle.kts") == 1
  then
    return "gradle"
  end

  return "unknown"
end

-- Get project dependencies classpath
function M.get_project_classpath()
  local project_type = M.detect_project_type()
  local classpath = {}

  if project_type == "maven" then
    -- Use Maven to get classpath
    local maven_cmd = "mvn dependency:build-classpath -DincludeScope=runtime -q"
    local output = vim.fn.system(maven_cmd)
    if vim.v.shell_error == 0 then
      for line in output:gmatch("[^\r\n]+") do
        if line:match("^/") or line:match("^[A-Z]:") then
          table.insert(classpath, line)
        end
      end
    end
  elseif project_type == "gradle" then
    -- Use Gradle to get classpath
    local gradle_cmd = "./gradlew dependencies --configuration runtimeClasspath"
    -- This is more complex and usually handled by JDTLS
  end

  return classpath
end

-- Get Spring Boot properties
function M.get_spring_boot_properties()
  local root_dir = vim.fn.getcwd()
  local props_file = root_dir .. "/src/main/resources/application.properties"
  local yml_file = root_dir .. "/src/main/resources/application.yml"

  if vim.fn.filereadable(props_file) == 1 then
    return props_file
  elseif vim.fn.filereadable(yml_file) == 1 then
    return yml_file
  end

  return nil
end

-- Check if project is Spring Boot
function M.is_spring_boot_project()
  local root_dir = vim.fn.getcwd()

  -- Check for Spring Boot starters in pom.xml
  if vim.fn.filereadable(root_dir .. "/pom.xml") == 1 then
    local pom_content = vim.fn.readfile(root_dir .. "/pom.xml")
    for _, line in ipairs(pom_content) do
      if line:match("spring%-boot%-starter") then
        return true
      end
    end
  end

  -- Check for Spring Boot in build.gradle
  if vim.fn.filereadable(root_dir .. "/build.gradle") == 1 then
    local gradle_content = vim.fn.readfile(root_dir .. "/build.gradle")
    for _, line in ipairs(gradle_content) do
      if line:match("spring%-boot") then
        return true
      end
    end
  end

  return false
end

-- Check if project is Quarkus
function M.is_quarkus_project()
  local root_dir = vim.fn.getcwd()

  -- Check for Quarkus dependencies
  if vim.fn.filereadable(root_dir .. "/pom.xml") == 1 then
    local pom_content = vim.fn.readfile(root_dir .. "/pom.xml")
    for _, line in ipairs(pom_content) do
      if line:match("quarkus") then
        return true
      end
    end
  end

  -- Check for Quarkus in build.gradle
  if
    vim.fn.filereadable(root_dir .. "/build.gradle") == 1
    or vim.fn.filereadable(root_dir .. "/build.gradle.kts") == 1
  then
    local gradle_file = vim.fn.filereadable(root_dir .. "/build.gradle") == 1 and root_dir .. "/build.gradle"
      or root_dir .. "/build.gradle.kts"
    local gradle_content = vim.fn.readfile(gradle_file)
    for _, line in ipairs(gradle_content) do
      if line:match("quarkus") then
        return true
      end
    end
  end

  return false
end

-- Validate all required paths exist
function M.validate_paths()
  local issues = {}

  local jdtls_path = M.get_jdtls_path()
  if not jdtls_path then
    table.insert(issues, "JDTLS not found. Install with: :MasonInstall jdtls")
  end

  local lombok_path = M.get_lombok_path()
  if not lombok_path then
    table.insert(issues, "Lombok JAR not found in JDTLS installation")
  end

  local config_dir = M.get_jdtls_config_dir()
  if not config_dir then
    table.insert(issues, "JDTLS config directory not found")
  end

  return issues
end

-- Print debug information
function M.debug_info()
  local info = {
    java_home = M.get_java_home(),
    jdtls_path = M.get_jdtls_path(),
    lombok_path = M.get_lombok_path(),
    config_dir = M.get_jdtls_config_dir(),
    debug_adapter = M.get_java_debug_adapter_path(),
    test_adapter = M.get_java_test_adapter_path(),
    workspace_dir = M.get_workspace_dir(),
    project_type = M.detect_project_type(),
    is_spring_boot = M.is_spring_boot_project(),
    is_quarkus = M.is_quarkus_project(),
    bundles_count = #M.get_bundles(),
  }

  print("Java Environment Debug Info:")
  print(vim.inspect(info))

  local issues = M.validate_paths()
  if #issues > 0 then
    print("\nIssues found:")
    for _, issue in ipairs(issues) do
      print("  - " .. issue)
    end
  else
    print("\n✓ All paths validated successfully")
  end

  return info
end

return M
