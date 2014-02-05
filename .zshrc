# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="mgalgs"

# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Comment this out to disable bi-weekly auto-update checks
# DISABLE_AUTO_UPDATE="true"

# Uncomment to change how often before auto-updates occur? (in days)
# export UPDATE_ZSH_DAYS=13

# Uncomment following line if you want to disable colors in ls
# DISABLE_LS_COLORS="true"

# Uncomment following line if you want to disable autosetting terminal title.
# DISABLE_AUTO_TITLE="true"

# Uncomment following line if you want to disable command autocorrection
DISABLE_CORRECTION="true"

# Uncomment following line if you want red dots to be displayed while waiting for completion
# COMPLETION_WAITING_DOTS="true"

# Uncomment following line if you want to disable marking untracked files under
# VCS as dirty. This makes repository status check for large repositories much,
# much faster.
# DISABLE_UNTRACKED_FILES_DIRTY="true"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(gitfast nyan web-search)

source $ZSH/oh-my-zsh.sh

# Customize to your needs...
path=(
    /usr/local/sbin
    /usr/local/bin
    /usr/bin
    /usr/bin/core_perl
    /usr/bin/vendor_perl
    $HOME/scripts
    $HOME/qbin
    $HOME/bin
    $HOME/bin/emacs-git/bin
    $HOME/bin/emacs-my-24.3/bin
)

source /usr/share/doc/pkgfile/command-not-found.zsh

_my_rdesktop_local_sound="-r disk:tmp=/tmp -r sound:local"
alias grquickhead="git grquick | head"
alias grjustmehead="git grjustme | head"
alias em="emacs -Q -nw --eval '(ido-mode)'"
alias emc='emacsclient -n -a emacs'
alias vm='emacsclient -nw -a emacs -nw'
alias gistatus='git status'
alias hilite='src-hilite-lesspipe.sh'
alias pidgin_fixed="NSS_SSL_CBC_RANDOM_IV=0 pidgin"
alias akmsg="adb wait-for-device; adb root; sleep 1; adb wait-for-device; adb shell cat /proc/kmsg"
alias alogcat="adb wait-for-device; sleep 5; adb wait-for-device; adb logcat"
alias jsonprettydump="python -c 'import json,sys; print json.dumps(json.load(sys.stdin), indent=4)'"
alias ls='ls -B --color=auto'

# fix up some aliases from oh-my-zsh plugins:
unalias gm
compdef _graphicsmagick gm

meldindexagainstpatch() { meld <(git diff --cached) <(git show $1); }
# the cat is to prevent accidentally saving rebase-apply/patch:
meldindexagainstrebasepatch() { meld <(git diff --cached) <(cat $(git rev-parse --show-toplevel)/.git/rebase-apply/patch); }

export GREP_OPTIONS='--exclude=*~'

manopt() { man $1 | sed -n "/^\s\+-\+$2\b/,/^\s*$/p"|sed '$d;'; } 

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
export LESSOPEN="| src-hilite-lesspipe.sh %s"
export LESS=' -i -R '

# don't kill (or notify me about) backgrounded processes on exit:
setopt no_check_jobs
setopt no_hup
# override from ~/.oh-my-zsh/lib/history.zsh:
setopt no_share_history

## don't complete backup files as executables
zstyle ':completion:*:complete:-command-::commands' ignored-patterns '*\~'

# remember recent working directories. See zshcontrib(1).
autoload -Uz chpwd_recent_dirs cdr add-zsh-hook
add-zsh-hook chpwd chpwd_recent_dirs

setopt interactivecomments

autoload edit-command-line
zle -N edit-command-line
bindkey '^Xe' edit-command-line

bindkey '^U' backward-kill-line

# reverse search with globbing
bindkey '^r' history-incremental-pattern-search-backward

[[ -r ~/private.zsh ]] && source ~/private.zsh
