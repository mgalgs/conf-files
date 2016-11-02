[[ $TERM == "dumb" ]] && unsetopt zle && PS1='$ ' && return

[[ -r ~/private-pre.zsh ]] && source ~/private-pre.zsh

# Path to your oh-my-zsh configuration.
ZSH=$HOME/.oh-my-zsh

export TERM=xterm-256color
# export TERM=screen-256color

# Set name of the theme to load.
# Look in ~/.oh-my-zsh/themes/
# Optionally, if you set this to "random", it'll load a random theme each
# time that oh-my-zsh is loaded.
ZSH_THEME="mgalgs"
[[ -e ~/.zsh-theme-setup.sh ]] && source ~/.zsh-theme-setup.sh

# Example aliases
# alias zshconfig="mate ~/.zshrc"
# alias ohmyzsh="mate ~/.oh-my-zsh"

# Set to this to use case-sensitive completion
# CASE_SENSITIVE="true"

# Uncomment this to disable bi-weekly auto-update checks
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
DISABLE_UNTRACKED_FILES_DIRTY="true"

# Uncomment following line if you want to  shown in the command execution time stamp 
# in the history command output. The optional three formats: "mm/dd/yyyy"|"dd.mm.yyyy"|
# yyyy-mm-dd
# HIST_STAMPS="mm/dd/yyyy"

# Which plugins would you like to load? (plugins can be found in ~/.oh-my-zsh/plugins/*)
# Custom plugins may be added to ~/.oh-my-zsh/custom/plugins/
# Example format: plugins=(rails git textmate ruby lighthouse)
plugins=(gitfast brew golang fabric pip npm bower)

source $ZSH/oh-my-zsh.sh

export GOPATH=$HOME/go

# Customize to your needs...
path=(
    /usr/lib/ccache/bin
    /usr/local/sbin
    /usr/local/bin
    /usr/sbin
    /usr/bin
    /usr/bin/core_perl
    /usr/bin/vendor_perl
    /sbin
    /bin
    $HOME/scripts
    $HOME/qbin
    $HOME/opt/emacs-git/bin
    $HOME/opt/bin
    $GOPATH/bin
)

export CCACHE_DIR=$HOME/ccache

[[ -r /usr/share/doc/pkgfile/command-not-found.zsh ]] && source /usr/share/doc/pkgfile/command-not-found.zsh

selfmail()
{
    msmtp -a default mitch.special@gmail.com <<<"To: mitch.special@gmail.com
From: mitch.special@gmail.com
Subject: selfmail: $1

$2"
}
# depends on setopt extendedglob:
alias croot='cd (../)#.repo(:h)'

# fix up some aliases from oh-my-zsh plugins:
unalias gm
compdef _graphicsmagick gm

meldindexagainstpatch() { meld <(git diff --cached) <(git show $1); }
# the cat is to prevent accidentally saving rebase-apply/patch:
meldindexagainstrebasepatch() { meld <(git diff --cached) <(cat $(git rev-parse --show-toplevel)/.git/rebase-apply/patch); }
meldindexagainstcherrypickhead() { meld <(git diff --cached) <(git show $(cat $(git rev-parse --show-toplevel)/.git/CHERRY_PICK_HEAD)); }

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
setopt interactivecomments
setopt extendedglob
HISTSIZE=50000
SAVEHIST=50000

## don't complete backup files as executables
zstyle ':completion:*:complete:-command-::commands' ignored-patterns '*\~'

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

source ~/scripts/dot_useful_aliases

PATH="`ruby -rubygems -e 'puts Gem.user_dir'`/bin:$PATH"

[[ -r ~/private.zsh ]] && source ~/private.zsh

source /usr/share/nvm/init-nvm.sh
