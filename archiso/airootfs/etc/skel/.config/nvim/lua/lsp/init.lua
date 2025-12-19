-- LSP Entry Point - Import all language configurations
-- Enable/disable languages by commenting/uncommenting

-- Programming Languages
require("lsp.java")       -- Java (Spring Boot, Quarkus, Maven, Gradle)
require("lsp.kotlin")     -- Kotlin
require("lsp.c-cpp")      -- C/C++
require("lsp.typescript") -- TypeScript/JavaScript
require("lsp.go")         -- Go
require("lsp.rust")       -- Rust
require("lsp.zig")        -- Zig

-- Web Development
require("lsp.web")        -- HTML/CSS/SCSS/TailwindCSS

-- Shell Scripting
require("lsp.shell")      -- Bash/Zsh

-- Databases
require("lsp.sql")        -- SQL (PostgreSQL, MySQL, SQLite)

-- Data Formats
require("lsp.data")       -- YAML/JSON/XML
require("lsp.openapi")    -- OpenAPI/Swagger (API specs)

-- DevOps
require("lsp.docker")     -- Docker & Docker Compose
require("lsp.kubernetes") -- Kubernetes & Helm

-- Documentation
require("lsp.latex")      -- LaTeX
require("lsp.markdown")   -- Markdown
require("lsp.asciidoc")   -- Asciidoc

vim.notify("All LSP configurations loaded", vim.log.levels.INFO)
