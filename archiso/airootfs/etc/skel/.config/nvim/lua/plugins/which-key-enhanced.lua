-- ═══════════════════════════════════════════════════════════
--           WHICH-KEY - ENHANCED KEYBINDING DISCOVERY
-- ═══════════════════════════════════════════════════════════
--
-- Extends LazyVim's which-key configuration with custom groups
-- Uses the new which-key v3 API (spec format)
-- IMPORTANT: This EXTENDS LazyVim's defaults, does NOT replace them
--
-- ═══════════════════════════════════════════════════════════

return {
  "folke/which-key.nvim",
  opts = function(_, opts)
    -- Ensure spec exists
    opts.spec = opts.spec or {}

    -- EXTEND LazyVim's spec with our custom keybinding groups
    -- This adds to existing bindings, does not replace them
    local custom_spec = {
      -- AI / Code Assistant
      { "<leader>a", group = "ai" },

      -- Outline / Symbol Navigation
      { "<leader>o", group = "outline" },

      -- Database (using <leader>D for database, move Docker elsewhere)
      { "<leader>D", group = "database" },
      { "<leader>Db", desc = "Database: Toggle UI" },
      { "<leader>Df", desc = "Database: Find Buffer" },
      { "<leader>Dr", desc = "Database: Rename Buffer" },
      { "<leader>Dq", desc = "Database: Last Query" },

      -- Docker (using <leader>cd for "container/docker")
      { "<leader>cd", group = "docker/container" },
      { "<leader>cdb", desc = "Docker: Build Image" },
      { "<leader>cdr", desc = "Docker: Run Container" },
      { "<leader>cdl", desc = "Docker: List Containers" },
      { "<leader>cdi", desc = "Docker: List Images" },
      { "<leader>cdc", desc = "Docker: Container Logs" },
      { "<leader>cde", desc = "Docker: Exec into Container" },
      { "<leader>cdu", desc = "Docker: Compose Up" },
      { "<leader>cdd", desc = "Docker: Compose Down" },
      { "<leader>cds", desc = "Docker: Compose Status" },
      { "<leader>cdL", desc = "Docker: Compose Logs" },

      -- Kubernetes (using <leader>ck for "container/kubernetes")
      { "<leader>ck", group = "kubernetes" },
      { "<leader>cka", desc = "K8s: Apply Manifest" },
      { "<leader>ckd", desc = "K8s: Delete Manifest" },
      { "<leader>ckv", desc = "K8s: Validate Manifest" },
      { "<leader>ckg", desc = "K8s: Get Resources" },
      { "<leader>ckl", desc = "K8s: Pod Logs" },
      { "<leader>cke", desc = "K8s: Exec into Pod" },
      { "<leader>cks", desc = "K8s: Describe Resource" },
      { "<leader>ckp", desc = "K8s: Port Forward" },
      { "<leader>ckn", desc = "K8s: List Namespaces" },
      { "<leader>ckc", desc = "K8s: Get Contexts" },
      { "<leader>ckh", desc = "Helm: Lint" },
      { "<leader>ckt", desc = "Helm: Template" },
      { "<leader>cki", desc = "Helm: Install" },

      -- Inline diagnostics toggle
      { "<leader>ci", desc = "Toggle inline diagnostics" },

      -- Color tools (extend code group)
      { "<leader>cp", desc = "Color: Pick" },
      { "<leader>cc", desc = "Color: Convert Format" },
      { "<leader>ch", desc = "Color: Toggle Highlighter" },
      { "<leader>ct", desc = "Color: Toggle Colorizer" },

      -- REST Client (extend refactor group)
      { "<leader>rr", desc = "REST: Run Request" },
      { "<leader>ra", desc = "REST: Run All" },
      { "<leader>rR", desc = "REST: Replay Last" },
      { "<leader>rn", desc = "REST: Next Request" },
      { "<leader>rp", desc = "REST: Previous Request" },
      { "<leader>rv", desc = "REST: Toggle View" },
      { "<leader>ri", desc = "REST: Inspect" },
      { "<leader>rh", desc = "REST: Show Stats" },
      { "<leader>rc", desc = "REST: Copy as cURL" },
      { "<leader>re", desc = "REST: Select Env" },
      { "<leader>rE", desc = "REST: Show Env" },
      { "<leader>rs", desc = "REST: Search Requests" },
      { "<leader>rt", desc = "REST: Scratchpad" },

      -- Screenshots (extend search group)
      { "<leader>sc", desc = "Screenshot: Capture", mode = "v" },
      { "<leader>sC", desc = "Screenshot: Capture File" },
      { "<leader>sb", desc = "Screenshot: Copy to Clipboard", mode = "v" },

      -- Startup Time
      { "<leader>st", desc = "Startup Time" },

      -- Tmux/Vimux Integration
      { "<leader>v", group = "tmux/vimux" },
      { "<leader>vp", desc = "Tmux: Prompt Command" },
      { "<leader>vl", desc = "Tmux: Run Last Command" },
      { "<leader>vr", desc = "Tmux: Run Current File" },
      { "<leader>vi", desc = "Tmux: Inspect Runner" },
      { "<leader>vz", desc = "Tmux: Zoom Runner" },
      { "<leader>vx", desc = "Tmux: Interrupt Runner" },
      { "<leader>vc", desc = "Tmux: Clear Screen" },
      { "<leader>vq", desc = "Tmux: Close Runner" },
      { "<leader>vt", desc = "Tmux: Toggle Pane" },
      { "<leader>vs", desc = "Tmux: Send Selection", mode = "v" },

      -- Comment Box
      { "<leader>C", group = "comment-box" },
      { "<leader>Cb", desc = "Box: Left-aligned" },
      { "<leader>CB", desc = "Box: Centered" },
      { "<leader>Cl", desc = "Box: Simple Line" },
      { "<leader>CL", desc = "Box: Centered Compact" },
      { "<leader>Ct", desc = "Box: Titled" },
      { "<leader>CT", desc = "Box: Centered Titled" },
      { "<leader>Ca", desc = "Box: Adaptive" },
      { "<leader>CA", desc = "Box: Adaptive Centered" },
      { "<leader>Cc", desc = "Box: Clean" },
      { "<leader>Cs", desc = "Box: Section Header" },
      { "<leader>Cn", desc = "Box: NOTE" },
      { "<leader>Cw", desc = "Box: WARNING" },
      { "<leader>Cd", desc = "Box: Remove" },
      { "<leader>Ce", desc = "Box: API Endpoint" },
      { "<leader>Cx", desc = "Box: TODO" },
      { "<leader>Cf", desc = "Box: FIXME" },
      { "<leader>Ci", desc = "Box: Class/Interface" },

      -- Pair Programming
      { "<leader>P", group = "pair-programming" },
      { "<leader>Ps", desc = "Pair: Start Server" },
      { "<leader>PS", desc = "Pair: Start Session" },
      { "<leader>Pj", desc = "Pair: Join Session" },
      { "<leader>Pf", desc = "Pair: Follow Partner" },
      { "<leader>PF", desc = "Pair: Stop Following" },
      { "<leader>Pt", desc = "Pair: Find TODOs" },
      { "<leader>Pq", desc = "Pair: Stop Session" },
      { "<leader>P/", desc = "Pair: Toggle Comment" },
      { "<leader>Pn", desc = "Pair: Next TODO" },
      { "<leader>Pp", desc = "Pair: Previous TODO" },
      { "<leader>Pl", desc = "Pair: TODO Location List" },
      { "<leader>Pb", desc = "Pair: Toggle Git Blame" },
      { "<leader>Po", desc = "Pair: Open Commit URL" },
      { "<leader>Pc", desc = "Pair: Copy Commit SHA" },
      { "<leader>Pu", desc = "Pair: Copy Commit URL" },
      { "<leader>Pa", desc = "Pair: Generate Annotation" },

      -- Harpoon
      { "<leader>h", group = "harpoon" },
      { "<leader>ha", desc = "Harpoon: Add File" },
      { "<leader>he", desc = "Harpoon: Toggle Menu" },
      { "<leader>h1", desc = "Harpoon: File 1" },
      { "<leader>h2", desc = "Harpoon: File 2" },
      { "<leader>h3", desc = "Harpoon: File 3" },
      { "<leader>h4", desc = "Harpoon: File 4" },

      -- Marks
      { "<leader>m", desc = "Marks: List Buffer Marks" },

      -- Undotree (extend ui group)
      { "<leader>ut", desc = "Toggle Undo Tree" },
    }

    -- Add our custom spec to LazyVim's spec
    vim.list_extend(opts.spec, custom_spec)

    return opts
  end,
}
