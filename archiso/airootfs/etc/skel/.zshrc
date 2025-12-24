# ShedOS Zsh Configuration
# Theme: Catppuccin Mocha

# ─────────────────────────────────────────────────────────────
# Oh My Zsh Configuration
# ─────────────────────────────────────────────────────────────

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

export ZSH="$HOME/.oh-my-zsh"

# Theme (will use starship instead)
ZSH_THEME="powerlevel10k/powerlevel10k"

# Plugins
plugins=(
    git
    docker
    docker-compose
    kubectl
    helm
    terraform
    ansible
    aws
    gcloud
    rust
    golang
    python
    pip
    npm
    yarn
    node
    sudo
    extract
    z
    fzf
    command-not-found
    colored-man-pages
    safe-paste
    history-substring-search
	colored-man-pages
	web-search
	aliases
	colorize
	encode64
	genpass
	history
    asdf
	zsh-autosuggestions
	zsh-syntax-highlighting
	screen
	ssh-agent
	urltools
	gnu-utils
	mvn
	postgres
	redis-cli
	vagrant
	nvm
	battery
	themes
)

# Oh My Zsh settings
COMPLETION_WAITING_DOTS="true"
DISABLE_UNTRACKED_FILES_DIRTY="true"

source $ZSH/oh-my-zsh.sh

# ─────────────────────────────────────────────────────────────
# Environment Variables
# ─────────────────────────────────────────────────────────────

# Editors
export EDITOR="nvim"
export VISUAL="nvim"
export SUDO_EDITOR="nvim"

# Browser
export BROWSER="firefox"

# Terminal
export TERMINAL="kitty"

# XDG Base Directories
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_STATE_HOME="$HOME/.local/state"
export XDG_CACHE_HOME="$HOME/.cache"

# Language
export LANG="en_US.UTF-8"
export LC_ALL="en_US.UTF-8"

# Path additions
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/.cargo/bin:$PATH"
export PATH="$HOME/go/bin:$PATH"


# Man pages
export MANPAGER="nvim +Man!"
export MANWIDTH=999

# ─────────────────────────────────────────────────────────────
# mise (runtime version manager)
# ─────────────────────────────────────────────────────────────

if command -v mise &> /dev/null; then
    eval "$(mise activate zsh)"
fi

# ─────────────────────────────────────────────────────────────
# Starship Prompt
# ─────────────────────────────────────────────────────────────

eval "$(starship init zsh)"

# ─────────────────────────────────────────────────────────────
# Modern CLI Replacements
# ─────────────────────────────────────────────────────────────

# eza (better ls)
if command -v eza &> /dev/null; then
    alias ls="eza --icons --group-directories-first"
    alias ll="eza -la --icons --group-directories-first"
    alias lt="eza -T --icons --level=2"
    alias la="eza -a --icons --group-directories-first"
fi

# bat (better cat)
if command -v bat &> /dev/null; then
    alias cat="bat --style=plain"
    alias catp="bat"
    export BAT_THEME="Catppuccin-mocha"
fi

# zoxide (better cd)
if command -v zoxide &> /dev/null; then
    eval "$(zoxide init zsh)"
    alias cd="z"
fi

# fd (better find)
if command -v fd &> /dev/null; then
    alias find="fd"
fi

# ripgrep (better grep)
if command -v rg &> /dev/null; then
    alias grep="rg"
fi

# dust (better du)
if command -v dust &> /dev/null; then
    alias du="dust"
fi

# duf (better df)
if command -v duf &> /dev/null; then
    alias df="duf"
fi

# procs (better ps)
if command -v procs &> /dev/null; then
    alias ps="procs"
fi

# bottom (better top)
if command -v btm &> /dev/null; then
    alias top="btm"
fi

# ─────────────────────────────────────────────────────────────
# Git Aliases
# ─────────────────────────────────────────────────────────────

alias g="git"
alias ga="git add"
alias gaa="git add --all"
alias gc="git commit -v"
alias gcm="git commit -m"
alias gco="git checkout"
alias gcb="git checkout -b"
alias gd="git diff"
alias gds="git diff --staged"
alias gf="git fetch"
alias gl="git pull"
alias gp="git push"
alias gst="git status"
alias glog="git log --oneline --graph --all"
alias lg="lazygit"

# ─────────────────────────────────────────────────────────────
# Docker Aliases
# ─────────────────────────────────────────────────────────────

alias d="docker"
alias dc="docker-compose"
alias dps="docker ps"
alias dpsa="docker ps -a"
alias di="docker images"
alias drm="docker rm"
alias drmi="docker rmi"
alias dex="docker exec -it"
alias dlogs="docker logs -f"
alias lzd="lazydocker"

# ─────────────────────────────────────────────────────────────
# Kubernetes Aliases
# ─────────────────────────────────────────────────────────────

alias k="kubectl"
alias kgp="kubectl get pods"
alias kgs="kubectl get services"
alias kgd="kubectl get deployments"
alias kgn="kubectl get nodes"
alias kdp="kubectl describe pod"
alias klogs="kubectl logs -f"
alias kex="kubectl exec -it"
alias kctx="kubectx"
alias kns="kubens"

# ─────────────────────────────────────────────────────────────
# System Aliases
# ─────────────────────────────────────────────────────────────

alias v="nvim"
alias vim="nvim"
alias vi="nvim"
alias c="clear"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias mkdir="mkdir -pv"
alias cp="cp -iv"
alias mv="mv -iv"
alias rm="rm -iv"
alias ports="ss -tulpn"

# Pacman aliases
alias pac="sudo pacman"
alias pacs="sudo pacman -S"
alias pacr="sudo pacman -Rns"
alias pacu="sudo pacman -Syu"
alias pacq="pacman -Qs"
alias pacss="pacman -Ss"

# Yay aliases
alias yas="yay -S"
alias yar="yay -Rns"
alias yau="yay -Syu"
alias yasr="yay -Ss"

# ─────────────────────────────────────────────────────────────
# FZF Configuration
# ─────────────────────────────────────────────────────────────

# Catppuccin Mocha colors
export FZF_DEFAULT_OPTS=" \
--color=bg+:#313244,bg:#1e1e2e,spinner:#f5e0dc,hl:#f38ba8 \
--color=fg:#cdd6f4,header:#f38ba8,info:#cba6f7,pointer:#f5e0dc \
--color=marker:#f5e0dc,fg+:#cdd6f4,prompt:#cba6f7,hl+:#f38ba8 \
--border='rounded' --border-label='' --preview-window='border-rounded' \
--prompt=' ' --marker='󰸞 ' --pointer=' ' --separator='─'"

# Use fd for fzf
export FZF_DEFAULT_COMMAND="fd --type f --hidden --follow --exclude .git"
export FZF_CTRL_T_COMMAND="$FZF_DEFAULT_COMMAND"
export FZF_ALT_C_COMMAND="fd --type d --hidden --follow --exclude .git"

# Enable fzf
[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh
[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh

# ─────────────────────────────────────────────────────────────
# Direnv
# ─────────────────────────────────────────────────────────────

if command -v direnv &> /dev/null; then
    eval "$(direnv hook zsh)"
fi

# ─────────────────────────────────────────────────────────────
# History Configuration
# ─────────────────────────────────────────────────────────────

HISTSIZE=50000
SAVEHIST=50000
HISTFILE=~/.zsh_history
setopt EXTENDED_HISTORY
setopt HIST_EXPIRE_DUPS_FIRST
setopt HIST_IGNORE_DUPS
setopt HIST_IGNORE_SPACE
setopt HIST_VERIFY
setopt SHARE_HISTORY

# ─────────────────────────────────────────────────────────────
# Zsh Options
# ─────────────────────────────────────────────────────────────

setopt AUTO_CD
setopt AUTO_PUSHD
setopt PUSHD_IGNORE_DUPS
setopt PUSHD_SILENT
setopt CORRECT
setopt CORRECT_ALL
setopt NO_BEEP
setopt INTERACTIVE_COMMENTS

# ─────────────────────────────────────────────────────────────
# Additional Plugins (external)
# ─────────────────────────────────────────────────────────────

# Syntax highlighting
[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ] && \
    source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Auto-suggestions
[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ] && \
    source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh

# ─────────────────────────────────────────────────────────────
# Custom Functions
# ─────────────────────────────────────────────────────────────

# Create directory and cd into it
mkcd() {
    mkdir -p "$1" && cd "$1"
}

# Extract any archive
extract() {
    if [ -f "$1" ]; then
        case "$1" in
            *.tar.bz2)   tar xjf "$1"     ;;
            *.tar.gz)    tar xzf "$1"     ;;
            *.tar.xz)    tar xJf "$1"     ;;
            *.bz2)       bunzip2 "$1"     ;;
            *.rar)       unrar x "$1"     ;;
            *.gz)        gunzip "$1"      ;;
            *.tar)       tar xf "$1"      ;;
            *.tbz2)      tar xjf "$1"     ;;
            *.tgz)       tar xzf "$1"     ;;
            *.zip)       unzip "$1"       ;;
            *.Z)         uncompress "$1"  ;;
            *.7z)        7z x "$1"        ;;
            *)           echo "'$1' cannot be extracted via extract()" ;;
        esac
    else
        echo "'$1' is not a valid file"
    fi
}

# Find in files
fif() {
    rg --column --line-number --no-heading --color=always --smart-case "$@" |
        fzf --ansi --delimiter : \
            --preview 'bat --style=numbers --color=always --highlight-line {2} {1}' \
            --preview-window up,60%,border-bottom
}

# ─────────────────────────────────────────────────────────────
# ShedOS Welcome
# ─────────────────────────────────────────────────────────────

if [[ -o interactive ]]; then
    fastfetch 2>/dev/null || neofetch 2>/dev/null || true
fi

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source "$HOME/.p10k.zsh"
