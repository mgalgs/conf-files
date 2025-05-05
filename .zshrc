# Fix for tramp
[[ $TERM == "dumb" ]] && unsetopt zle && PS1='$ ' && return

# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

source_if_exists() {
  [[ -r "$1" ]] && source "$1"
}

source_if_exists ~/private-pre.zsh

autoload -Uz compinit
compinit
zmodload zsh/complist # needed for colored completion menu

# Set CONF_FILES according to your setup
export ZALGZ_BASE_DIR="$HOME/conf-files/zalgz"
# Define a debugging level; set to 0 to disable debugging
export ZALGZ_DEBUG_LEVEL=0
source "$ZALGZ_BASE_DIR/zalgz.zsh"

zalgz init

export TERM=xterm-256color
# export TERM=screen-256color

export GOPATH=$HOME/go

# Customize to your needs...
path+=(
    $HOME/scripts
    $HOME/opt/bin
    $GOPATH/bin
    $HOME/.local/bin
    $HOME/bin
    $HOME/.pub-cache/bin
)

export CCACHE_DIR=$HOME/ccache

source_if_exists /usr/share/doc/pkgfile/command-not-found.zsh

# depends on setopt extendedglob:
alias croot='cd (../)#.git(:h)'

# colored man pages: :)
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;34m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

export ALTERNATE_EDITOR='emacs -Q -nw'
export EDITOR="emacsclient -nw -a vim"
export LESSOPEN="| /usr/bin/src-hilite-lesspipe.sh %s"
export LESS=' -i -R -S '

# don't kill (or notify me about) backgrounded processes on exit:
setopt no_check_jobs
setopt no_hup
setopt interactivecomments
setopt extendedglob

## History file configuration
HISTFILE="$HOME/.zsh_history"
HISTSIZE=50000
SAVEHIST=10000
setopt histignorespace
setopt no_share_history
setopt extended_history       # record timestamp of command in HISTFILE
setopt hist_expire_dups_first # delete duplicates first when HISTFILE size exceeds HISTSIZE
setopt hist_ignore_dups       # ignore duplicated commands history list
setopt hist_ignore_space      # ignore commands that start with space
setopt hist_verify            # show command with history expansion to user before running it
setopt inc_append_history     # write to history file immediately when command is executed

# emacs keybindings
bindkey -e

## Completion settings
# don't complete backup files as executables
zstyle ':completion:*:complete:-command-::commands' ignored-patterns '*\~'
# Use menu for completion
zstyle ':completion:*' menu select
# Completion matching
#  - 'm:{a-zA-Z}={A-Za-z}' :: Case insensitivity
#  - 'r:|[._-]=* r:|=*' :: Ignore punctuation (e.g. filetxt matches file.txt)
#  - 'l:|=* r:|=*' :: Match anywhere in the word
zstyle ':completion:*' matcher-list \
       'm:{a-zA-Z}={A-Za-z}' \
       'r:|[._-]=* r:|=*' \
       'l:|=* r:|=*'
# Enable colors for menu selection
#  - "di=34" :: Directory color (blue)
#  - "fi=0" :: Regular file color (default color)
#  - "mi=48;5;226" :: Highlight for currently selected item (black on yellow)
#  - "sl=30;47" :: Selection line (black on white)
#  - "hl=0;47" :: Highlighted completion matches (default on white)
zstyle ':completion:*:default' list-colors \
       "di=34" \
       "fi=0" \
       "mi=48;5;226" \
       "sl=30;47" \
       "hl=0;47"

# kubectl completion
[[ "$commands[kubectl]" ]] && source <(kubectl completion zsh)

# remember recent working directories. See zshcontrib(1).
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs

autoload edit-command-line
zle -N edit-command-line
bindkey '^Xe' edit-command-line

bindkey '^U' backward-kill-line

# reverse search with globbing
bindkey '^r' history-incremental-pattern-search-backward

autoload -U select-word-style
select-word-style bash

alias k=kubectl
alias emc="emacsclient -n -a emacs"
alias gsus='git status'
alias grquickhead="git grquick | head"
alias vm='emacsclient -nw -a em'
alias E="SUDO_EDITOR=\"emacsclient -nw\" sudoedit"
alias S="sudo pacman -S "
alias R="sudo pacman -R "
alias Sy="sudo pacman -Sy "
alias ls="ls --color=auto"
alias lse="lsd -l"
alias lsel="lsd -l"
alias ll="lsd -l"
alias lselt="lsd -lt"
type open >/dev/null || alias open="xdg-open"
alias ybat="bat -lyaml"
alias jbat="bat -ljson"

function lsenoobs() {
    lsd --color=always -lt $* | head
}

alias kasa="uvx --from python-kasa kasa"

function kasa-off() {
    kasa --host $1 --type plug off
}

function kasa-on() {
    kasa --host $1 --type plug on
}

# Function to perform completion by parsing /etc/hosts for kasa- prefixed hosts
_kasa_completion() {
    local -a hostnames
    # Parse /etc/hosts and extract hostnames starting with kasa-
    hostnames=($(awk '/kasa-/{print $2}' /etc/hosts | sort -u))

    # Define how the completion works, explicitly quoting the array expansion
    _describe 'hostname' hostnames -V hostnames
}

# Register the completion function for kasa-on and kasa-off
compdef _kasa_completion kasa-on
compdef _kasa_completion kasa-off

## fvm completion scripts setup. Remove the following line to uninstall
[[ -f "$HOME/.dart-cli-completion/zsh-config.zsh" ]] && . "$HOME/.dart-cli-completion/zsh-config.zsh" || true

source_if_exists ~/private.zsh

export ANDROID_EMULATOR_USE_SYSTEM_LIBS=1

source_if_exists /usr/share/fzf/key-bindings.zsh
source_if_exists /usr/share/fzf/completion.zsh
source_if_exists /usr/local/opt/fzf/shell/key-bindings.zsh
source_if_exists /usr/local/opt/fzf/shell/completion.zsh
source_if_exists /usr/share/doc/fzf/examples/key-bindings.zsh
source_if_exists /usr/share/doc/fzf/examples/completion.zsh
source_if_exists /usr/share/nvm/init-nvm.sh

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
# (installed via zalgz. update with: `zalgz update romkatv/powerlevel10k`)

# zsh-syntax-highlighting has to be sourced last, so rather than going
# through zalgz we just install it with the system package manager and
# source it here.
source_if_exists /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

# pnpm
export PNPM_HOME="$HOME/.local/share/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac
# pnpm end
