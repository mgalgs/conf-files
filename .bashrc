# .bashrc
# append to the history file, don't overwrite it
shopt -s histappend

# check the window size after each command and, if necessary,
# update the values of LINES and COLUMNS.
shopt -s checkwinsize

# If set, the pattern "**" used in a pathname expansion context will
# match all files and zero or more directories and subdirectories.
shopt -s globstar

# Add an "alert" alias for long running commands.  Use like so:
#   sleep 10; alert
alias alert='notify-send --urgency=low -i "$([ $? = 0 ] && echo terminal || echo error)" "$(history|tail -n1|sed -e '\''s/^\s*[0-9]\+\s*//;s/[;&|]\s*alert$//'\'')"'

# enable programmable completion features (you don't need to enable
# this, if it's already enabled in /etc/bash.bashrc and /etc/profile
# sources /etc/bash.bashrc).
if ! shopt -oq posix; then
  if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
  elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
  fi
fi

# Source global definitions
if [ -f /etc/bashrc ]; then
	. /etc/bashrc
fi

# User specific aliases and functions

export HISTSIZE=10000
source ~/scripts/util.sh

# my prompt:
source ~/scripts/dot_ansicolor
MYPS1FRONT="$C_BROWN(\w)\n$C_LIGHT_YELLOW \h$C_LIGHT_RED > $C_GREEN[$C_RED"
MYPS1BACK="$C_GREEN]$C_LIGHT_RED\$ $C_RESET"
PROMPT_COMMAND=myps1messages

export PATH=~/scripts:$PATH

export LESSOPEN="| src-hilite-lesspipe.sh %s"
export LESS=' -R '

export ALTERNATE_EDITOR='emacs -Q -nw'
export EDITOR="emacsclient -nw -a vim"
source ~/scripts/dot_useful_aliases

if [ -n "$DISPLAY" ]; then
     export BROWSER=chromium
fi

# colored man pages: :)
export LESS_TERMCAP_mb=$'\E[01;31m'
export LESS_TERMCAP_md=$'\E[01;34m'
export LESS_TERMCAP_me=$'\E[0m'
export LESS_TERMCAP_se=$'\E[0m'
export LESS_TERMCAP_so=$'\E[01;44;33m'
export LESS_TERMCAP_ue=$'\E[0m'
export LESS_TERMCAP_us=$'\E[01;32m'

alias pls='ls++ -t -B'

manopt() { man $1 | sed -n "/^\s\+-\+$2\b/,/^\s*$/p"|sed '$d;'; } 
alias hilite='src-hilite-lesspipe.sh'

[[ -e /usr/share/git/git-prompt.sh ]] && source /usr/share/git/git-prompt.sh
