-- LaTeX Snippets and Templates
local M = {}

function M.setup()
    -- Common LaTeX templates
    vim.api.nvim_create_user_command("LatexArticle", function()
        local template = [[
\documentclass[12pt,a4paper]{article}
\usepackage[utf8]{inputenc}
\usepackage[T1]{fontenc}
\usepackage{amsmath,amssymb}
\usepackage{graphicx}
\usepackage{hyperref}

\title{Title}
\author{Author}
\date{\today}

\begin{document}
\maketitle

\begin{abstract}
Abstract text here.
\end{abstract}

\section{Introduction}

\end{document}
]]
        vim.api.nvim_buf_set_lines(0, 0, -1, false, vim.split(template, "
"))
    end, { desc = "Insert article template" })
end

M.setup()
return M
