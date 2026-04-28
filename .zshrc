# Environment setup
eval "$(/opt/homebrew/bin/brew shellenv zsh)"

# Environment variables
export ZSH="$HOME/.oh-my-zsh"
export CLICOLOR=1
export EDITOR='vim'
export HOMEBREW_NO_INSTALL_CLEANUP=1
export HOMEBREW_UPGRADE_GREEDY=1
export HOMEBREW_UPGRADE_GREEDY_CASKS=1
export PATH=$/opt/homebrew/bin:HOME/bin:$HOME/.local/bin:/usr/local/bin:$PATH
export GITHUB_PERSONAL_ACCESS_TOKEN=$(security find-generic-password -s "github-token" -w)

# Disable theme (Starship takes over)
ZSH_THEME=""

# Plugins
plugins=(git copypath copyfile extract web-search)

# History settings
HISTFILE=~/.zsh_history
HISTSIZE=10000
SAVEHIST=10000
setopt SHARE_HISTORY HIST_IGNORE_DUPS HIST_IGNORE_SPACE

# Load Oh My Zsh
source $ZSH/oh-my-zsh.sh

# Completion settings
zstyle ":completion:*" menu select
zstyle ":completion:*" matcher-list "m:{a-zA-Z}={A-Za-z}"

# External tools
eval "$(starship init zsh)"
eval "$(zoxide init zsh)"
eval "$(tv init zsh)"
if command -v ngrok &>/dev/null; then
  eval "$(ngrok completion)"
fi
source <(fzf --zsh)
source <(kubectl completion zsh)
source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# Aliases
alias ~="cd ~"
alias ..="cd .."
alias ...="cd ../.."
alias ....="cd ../../.."
alias dev="cd ~/Developer"

alias tmux="zellij"
alias zshconfig="$EDITOR ~/.zshrc"
alias ohmyzsh="$EDITOR ~/.oh-my-zsh"

alias ip="curl -s https://ipinfo.io/ip && echo"
alias localip="hostname -I 2>/dev/null || ifconfig | grep 'inet ' | grep -v '127.0.0.1' | head -1 | awk '{print \$2}'"
alias ping="ping -c 5"
alias fuck="export https_proxy=http://127.0.0.1:7897;export http_proxy=http://127.0.0.1:7897;export all_proxy=socks5://127.0.0.1:7897"

alias brewup="brew update && brew upgrade && brew cleanup"
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

alias docker="podman"
alias docker-compose="podman-compose"
alias k8s="kubectl"

alias ll="eza -al --icons=auto --git-ignore"
alias tree="eza -al --tree -L 3 --icons=auto --git-ignore"
