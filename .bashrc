#
# ~/.bashrc
#

# If not running interactively, don't do anything
[[ $- != *i* ]] && return

export HISTSIZE=10000

#PS1='[\u@\h \W]\$ '

#source ~/school/and_such_as/scripts/util.sh
source ~/scripts/util.sh

# my prompt:
source ~/school/and_such_as/dot_rands/dot_ansicolor
MYPS1FRONT="$C_BROWN(\w)\n$C_LIGHT_BLUE \h$C_LIGHT_RED > $C_GREEN[$C_RED"
MYPS1BACK="$C_GREEN]$C_LIGHT_RED\$ $C_RESET"
PROMPT_COMMAND=myps1messages


complete -cf sudo
. /etc/bash_completion

#export PATH=/usr/lib/colorgcc/bin:/home/mgalgs/scripts:/home/mgalgs/bin:/home/mgalgs/school/and_such_as/scripts:${PATH}
export PATH=/home/mgalgs/scripts:/home/mgalgs/opt/bin:/home/mgalgs/bin:/home/mgalgs/school/and_such_as/scripts:${PATH}:/home/mgalgs/ppc/bin

special_compiler=ccache
if [[ $special_compiler == "ccache" ]]; then
    export PATH=/usr/lib/ccache/bin:$PATH
elif [[ $special_compiler == "colorgcc" ]]; then
    export PATH=/usr/lib/colorgcc/bin:$PATH
fi

# usually you modify PATH to activate ccache, but
# since we're using colorgcc we do it this way:
#export CCACHE_PATH="/usr/bin"
export CCACHE_LOGFILE="/home/mgalgs/.ccache.log"
#export CCACHE_NODIRECT=1

alias ls='ls --color=auto'
alias scr='screen -d -R'
alias sudo='sudo '		# to make aliases work
alias findcsources='find . \( -name "*.cpp" -o -name "*.c" -o -name "*.h" \)'
alias grep='grep --color=auto'
alias diff='colordiff'
export LESSOPEN="| src-hilite-lesspipe.sh %s"
export LESS=' -R '

source ~/workaliases.sh

export ALTERNATE_EDITOR='emacs -Q -nw'
export EDITOR="emacsclient -nw -a vim"
source ~/school/and_such_as/dot_rands/dot_useful_aliases

PYMACS_PYTHON=python2
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

export TERM="screen-256color"

alias man='man -P less'
alias pls='ls++ -t -B'

manopt() { man $1 | sed -n "/^\s\+-\+$2\b/,/^\s*$/p"|sed '$d;'; } 
alias hilite='src-hilite-lesspipe.sh'

export ACE_ROOT=/home/mgalgs/ACE_wrappers
export ACE_TAO=${ACE_ROOT}/TAO
export TAO_ROOT=${ACE_TAO}
export LD_LIBRARY_PATH=${ACE_ROOT}/lib:${ACE_ROOT}/ace:$LD_LIBRARY_PATH

alias clk='tmux new-session \; clock-mode'

complete -A hostname gssh
complete -f -A hostname gscp
