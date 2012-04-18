# .bashrc

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

export PATH=/home/mgalgs/scripts:$PATH

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

