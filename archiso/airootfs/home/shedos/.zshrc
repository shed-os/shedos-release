# ShedOS Default Zsh Configuration

# History
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY
setopt HIST_IGNORE_DUPS

# Key bindings - emacs style
bindkey -e

# Basic completion
autoload -Uz compinit
compinit

# Prompt
autoload -Uz promptinit
promptinit
PS1='%F{cyan}%n@%m%f:%F{blue}%~%f %# '

# Aliases
alias ls='ls --color=auto'
alias ll='ls -la'
alias grep='grep --color=auto'

# Start installer hint
echo ""
echo "Welcome to ShedOS Live Environment!"
echo "Run 'shedos-installer' to start the installation."
echo ""
