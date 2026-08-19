#!/usr/bin/env bash
# check-script-order.sh <script>…
#
# A variable read at the top level of a script before the line that sets it.
#
# Under `set -u` that is an immediate death, and it dies where the read is —
# which in a build script can be forty minutes in, after the expensive part has
# already run. It is also invisible to shellcheck, which sees the assignment
# and asks no question about where it sits, and invisible to `bash -n`, which
# never evaluates anything.
#
# The scope is deliberately narrow, because the wide version is noise: only
# statements at column zero are considered, only variables the same script sets
# at column zero, and only reads that carry no default of their own. Inside a
# function, order is a property of when the function is called rather than of
# where the line sits, and this says nothing about it.
set -uo pipefail

(( $# )) || { echo 'usage: check-script-order.sh <script>…' >&2; exit 2; }

python3 - "$@" <<'PY'
import re, sys

# $VAR, ${VAR}, ${VAR[i]} — but not ${VAR:-…}, ${VAR-…}, ${VAR:=…}, ${VAR+…},
# ${VAR:?…}, each of which says what to do when the variable is unset.
GUARDED = re.compile(r'\$\{([A-Za-z_][A-Za-z0-9_]*)(?:\[[^]]*\])?:?[-=?+]')
USE = re.compile(r'\$\{?([A-Za-z_][A-Za-z0-9_]*)')
ASSIGN = re.compile(
    r'^(?:export\s+|readonly\s+|declare\s+(?:-[A-Za-z]+\s+)*|typeset\s+)?'
    r'([A-Za-z_][A-Za-z0-9_]*)(?:\[[^]]*\])?(?:\+?=)')
FOR = re.compile(r'^for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in\b')
MAPFILE = re.compile(r'^mapfile\s+(?:-[A-Za-z]+\s+)*([A-Za-z_][A-Za-z0-9_]*)')
# `read -r name` sets it, and the same line often guards on it — `while read -r
# line || [[ -n $line ]]` is the standard way to take a file with no trailing
# newline, and reading that as a use before a set is wrong twice over.
READ = re.compile(r'\bread\s+(?:-[A-Za-z]+\s+)*((?:[A-Za-z_][A-Za-z0-9_]*\s*)+)')

def strip_quoted(text):
    """Blank out single-quoted runs, so a literal $pkgver in a PKGBUILD or an
    awk program is not read as this script's variable."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c == "'":
            j = text.find("'", i + 1)
            if j == -1:
                out.append(' ' * (n - i)); break
            out.append(' ' * (j - i + 1)); i = j + 1
            continue
        out.append(c); i += 1
    return ''.join(out)

findings = 0
for path in sys.argv[1:]:
    raw = open(path, encoding='utf-8', errors='replace').read().split('\n')

    # Heredoc bodies are skipped whole, quoted or not. A quoted one is data. An
    # unquoted one is expanded, but it sits at column zero inside whatever
    # construct opened it, so its position says nothing about scope — the body
    # of a heredoc inside a function is not a top-level statement.
    skip = [False] * len(raw)
    end = None
    for i, line in enumerate(raw):
        if end is not None:
            skip[i] = True
            if line.strip() == end:
                end = None
            continue
        m = re.search(r"""<<-?\s*'([^']+)'|<<-?\s*"([^"]+)"|<<-?\s*([A-Za-z_][A-Za-z0-9_]*)""", line)
        if m:
            end = m.group(1) or m.group(2) or m.group(3)

    top = []       # (lineno, code) for statements at column zero
    for i, line in enumerate(raw, 1):
        if skip[i - 1] or line.startswith((' ', '\t')) or not line.strip():
            continue
        if line.lstrip().startswith('#'):
            continue
        top.append((i, strip_quoted(line)))

    first_set = {}
    for lineno, code in top:
        for rx in (ASSIGN, FOR, MAPFILE):
            m = rx.match(code)
            if m and m.group(1) not in first_set:
                first_set[m.group(1)] = lineno
        m = READ.search(code)
        if m:
            for name in m.group(1).split():
                first_set.setdefault(name, lineno)

    for lineno, code in top:
        guarded = {m.group(1) for m in GUARDED.finditer(code)}
        # The assignment on this very line is not a read of itself.
        m = ASSIGN.match(code)
        own = m.group(1) if m else None
        for m in USE.finditer(code):
            name = m.group(1)
            if name in guarded or name == own:
                continue
            at = first_set.get(name)
            if at is not None and at > lineno:
                print(f'{path}:{lineno}: {name} is read here and set at line {at}')
                findings += 1

sys.exit(1 if findings else 0)
PY
