-- ═══════════════════════════════════════════════════════════
--                    LOMBOK SUPPORT
-- ═══════════════════════════════════════════════════════════
--
-- Lombok is a Java library that automatically generates boilerplate
-- code like getters, setters, constructors, equals, hashCode, toString.
--
-- This module ensures JDTLS properly recognizes Lombok annotations.
--
-- ═══════════════════════════════════════════════════════════

local M = {}

-- Check if Lombok is enabled
function M.is_enabled()
    return vim.g.lombok_support == 1
end

-- Download Lombok JAR if not present
function M.ensure_lombok()
    local paths = require("lsp.java.core.paths")
    local lombok_path = paths.get_lombok_path()

    if vim.fn.filereadable(lombok_path) == 0 then
        vim.notify("Downloading Lombok...", vim.log.levels.INFO)

        local lombok_url = "https://projectlombok.org/downloads/lombok.jar"
        local download_cmd = string.format("curl -fLo %s %s", lombok_path, lombok_url)

        vim.fn.system(download_cmd)

        if vim.v.shell_error == 0 then
            vim.notify("Lombok downloaded successfully", vim.log.levels.INFO)
        else
            vim.notify("Failed to download Lombok", vim.log.levels.ERROR)
        end
    end
end

-- Common Lombok annotations
M.annotations = {
    "@Data",
    "@Getter",
    "@Setter",
    "@ToString",
    "@EqualsAndHashCode",
    "@NoArgsConstructor",
    "@AllArgsConstructor",
    "@RequiredArgsConstructor",
    "@Builder",
    "@Value",
    "@SneakyThrows",
    "@Synchronized",
    "@Slf4j",
    "@Log",
    "@CommonsLog",
    "@Log4j",
    "@Log4j2",
    "@XSlf4j",
    "@NonNull",
    "@Cleanup",
    "@With",
    "@Singular",
    "@Delegate",
}

-- Create Lombok configuration file for the project
function M.create_lombok_config()
    local root_dir = vim.fn.getcwd()
    local lombok_config = root_dir .. "/lombok.config"

    -- Check if config already exists
    if vim.fn.filereadable(lombok_config) == 1 then
        return
    end

    local config_content = {
        "# Lombok configuration",
        "",
        "# Add generated annotations to methods",
        "lombok.addLombokGeneratedAnnotation = true",
        "",
        "# Configure field naming",
        "lombok.fieldNameConstants.uppercase = false",
        "",
        "# Enable builder support",
        "lombok.builder.className = Builder",
        "",
        "# Copy Javadoc comments to generated methods",
        "lombok.copyableAnnotations += org.springframework.beans.factory.annotation.Autowired",
        "lombok.copyableAnnotations += org.springframework.beans.factory.annotation.Qualifier",
        "lombok.copyableAnnotations += org.springframework.web.bind.annotation.RequestMapping",
        "",
        "# Slf4j configuration",
        "lombok.log.fieldName = log",
        "lombok.log.fieldIsStatic = true",
    }

    vim.fn.writefile(config_content, lombok_config)
    vim.notify("Created lombok.config", vim.log.levels.INFO)
end

-- Check if current file uses Lombok
function M.uses_lombok()
    local lines = vim.api.nvim_buf_get_lines(0, 0, 50, false)

    for _, line in ipairs(lines) do
        if line:match("^import%s+lombok%.") or line:match("@%w*Lombok") or line:match("@Data") or line:match("@Builder") then
            return true
        end
    end

    return false
end

-- Setup Lombok support
function M.setup()
    if not M.is_enabled() then
        return
    end

    -- Ensure Lombok JAR exists
    M.ensure_lombok()

    -- Create Lombok config for Spring Boot projects
    local paths = require("lsp.java.core.paths")
    if paths.is_spring_boot_project() then
        M.create_lombok_config()
    end

    -- Add Lombok-specific commands
    vim.api.nvim_create_user_command("LombokInfo", function()
        local uses_lombok = M.uses_lombok()
        local lombok_path = require("lsp.java.core.paths").get_lombok_path()

        local message = string.format(
            "Lombok Support:\n\nEnabled: %s\nCurrent file uses Lombok: %s\nLombok JAR: %s",
            M.is_enabled(),
            uses_lombok,
            lombok_path
        )

        vim.notify(message, vim.log.levels.INFO)
    end, { desc = "Show Lombok information" })

    -- Command to create lombok.config
    vim.api.nvim_create_user_command("LombokCreateConfig", function()
        M.create_lombok_config()
    end, { desc = "Create lombok.config" })

    -- Completion for Lombok annotations
    vim.api.nvim_create_autocmd("FileType", {
        pattern = "java",
        callback = function()
            -- Add Lombok annotations to completion
            if M.uses_lombok() then
                -- This will be integrated with the main completion system
            end
        end,
    })
end

return M
