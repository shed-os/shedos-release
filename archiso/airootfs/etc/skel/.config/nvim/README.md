# 🚀 Ultimate Neovim Configuration (LazyVim Enhanced)

A battle-tested, production-ready Neovim configuration built on [LazyVim](https://www.lazyvim.org/).
Designed for **full-stack engineering** with a focus on Java (Spring Boot), Rust, TypeScript, and DevOps.

## ✨ Key Features

- **Automated Toolchain**: **80+** LSPs, CLIs, Linters, and Formatters auto-installed via Mason.
- **Robust Formatting & Linting**:
    - **Conform.nvim** for formatting, tailored to respect your project dotfiles (`.stylua.toml`, etc.).
    - **Nvim-lint** for linting, wired to use your local config files (`.eslintrc.json`, `.golangci.yml`, `checkstyle.xml`, etc.).
    - **Intelligent Fallback**: No more "LSP Format Failed" errors. formatting fails silently if no tool is available.
- **Language Superpowers**:
    - **Java**: Full IDE experience. Custom **JPA Buddy++** features (SQL generation, DTO generation), Spring Boot integration, and Debugging.
    - **Rust**: Optimized `rustaceanvim` setup with `clippy` on save and error lens.
    - **TypeScript**: `tools.lua` loaded `eslint_d` with explicit config path resolving.
- **Custom Snippets**:
    - Centralized in `~/.config/nvim/snippets/*.lua`.
    - Framework-aware: Spring Boot snippets availble in `.java` files, NestJS in `.ts` files.
- **Clean UI**: Inlay hints disabled by default for a clutter-free experience.

## 📂 Directory Structure

```text
~/.config/nvim/
├── init.lua                        # Entry point (Monkey patches for stability)
├── lua/
│   ├── config/                     # Core Configuration
│   │   ├── autocmds.lua            # Automation & Patching
│   │   ├── keymaps.lua             # Custom Keymaps (adds to LazyVim defaults)
│   │   ├── lazy.lua                # Plugin Manager setup
│   │   └── options.lua             # Vim Options (UI, behavior)
│   │
│   └── plugins/                    # The Powerhouse
│       ├── formatting.lua          # conform.nvim (Formatters)
│       ├── linting.lua             # nvim-lint (Linters + Dotfile wiring)
│       ├── mason-tools.lua         # List of 80+ tools to auto-install
│       ├── snippets-enhanced.lua   # LuaSnip custom loader
│       ├── java.lua                # nvim-jdtls + JPA features
│       ├── rust.lua                # rustaceanvim config
│       ├── typescript.lua          # TypeScript/JS config
│       ├── ... (other langs)
│
├── snippets/                       # Custom Snippets Directory
│   ├── java.lua                    # Java/Spring snippets
│   ├── express-nestjs.lua          # TS/JS Framework snippets
│   └── ...
│
└── .config/                        # Dotfiles used by linters/formatters
    ├── .eslintrc.json
    ├── .golangci.yml
    ├── .stylua.toml
    ├── checkstyle.xml
    └── ...
```

## 🛠️ Tooling (Managed by Mason)

This config automatically installs and manages a massive suite of tools.
Run `:Mason` to see the full status.

| Category | Utilities included (partial list) |
| :--- | :--- |
| **LSPs** | `jdtls`, `rust-analyzer`, `tsserver`, `gopls`, `clangd`, `pyright`, `lua_ls`, `bashls`, `dockerls`, `yamlls`... |
| **Linters** | `eslint_d`, `checkstyle`, `golangci-lint`, `shellcheck`, `hadolint`, `sqlfluff`... |
| **Formatters**| `prettierd`, `google-java-format`, `shfmt`, `stylua`, `black`, `isort`, `clang-format`... |
| **Debuggers**| `java-debug-adapter`, `codelldb`, `delve` (go), `js-debug-adapter`... |

## ⌨️ Keymaps

This config inherits **ALL** standard [LazyVim Keymaps](https://www.lazyvim.org/keymaps).

### 🚀 Highlights (Built-in)
| Key | Action |
| :--- | :--- |
| `<space>e` | File Explorer (NeoTree) |
| `<space><space>` | Find Files |
| `<space>/` | Grep (Search in files) |
| `S-h` / `S-l` | Previous / Next Buffer |
| `gd` | Goto Definition |
| `gr` | Goto References |
| `<space>ca` | Code Action |

### 💎 Custom Java (JPA) Extensions
| Key | Action |
| :--- | :--- |
| `<leader>jr` | Compile & Run (Simple Java) |
| `<leader>js` | Generate SQL DDL for Entity |
| `<leader>jd` | Generate DTO from Entity |
| `<leader>jc` | Generate REST Controller |
| `<leader>jf` | Generate Flyway Migration |

### 🦀 Rust Extensions
| Key | Action |
| :--- | :--- |
| `<leader>rc` | Cargo Check |
| `<leader>rr` | Cargo Run |
| `<leader>rt` | Cargo Test |
| `<leader>rh` | Hover Actions |

## 🔧 Customization Guide

### 1. Formatting
Edit `lua/plugins/formatting.lua`.
We use `conform.nvim`. Default behavior:
*   Use `prettierd` for almost everything web-related.
*   Use specialized formatters (Go, Rust, Java) natively.
*   **Fallback**: Disabled globally to prevent errors.

### 2. Linting
Edit `lua/plugins/linting.lua`.
We use `nvim-lint`. New linters must be added to `linters_by_ft` AND have their `args` configured if they need specific config files (like `checkstyle.xml`).

### 3. Adding Snippets
Create a new file in `~/.config/nvim/snippets/my-lang.lua`.
It must return a Lua table of snippets (LuaSnip format).
**Important:** If the filename doesn't match the filetype (e.g. `spring.lua` for `java`), you must add a mapping in `lua/plugins/snippets-enhanced.lua` under `luasnip.filetype_extend`.

## 🆘 Troubleshooting

### "Format request failed"
We fixed this by patching `init.lua`. If you see it:
1.  Restart Neovim.
2.  Check `:checkhealth`.

### Linter not showing errors
1.  Verify the linter is installed (`:Mason`).
2.  Verify the config file exists in `~/.config/nvim/` (e.g., `.eslintrc.json`).
3.  Check `:LspInfo` to see if a conflicting LSP is actively suppressing it (rare).
