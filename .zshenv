# Sourced by EVERY zsh — interactive, non-interactive, and scripts —
# unlike .zshrc, which interactive shells alone read.
#
# node lives here rather than in .zshrc for one reason: a bash script
# (scripts/smoke.sh, a Makefile, a git hook) inherits PATH from whatever
# spawned it, but it can never call a zsh function. The lazy-load stubs
# in .zshrc only fire when you TYPE node/npm, so a script that merely
# runs `npm ci` never triggers them and falls through to /usr/bin/node
# with no npm beside it. Exporting the real bin dir here means every
# child process gets the same node and npm as the prompt.
#
# NVM_SYMLINK_CURRENT makes `nvm use` maintain ~/.nvm/current, so this
# needs no subshell and no sourcing of nvm.sh — the whole thing costs
# one string test per shell. The trade: `current` is global, so
# switching versions in one terminal changes what newly spawned
# processes see everywhere. That is the point — one node, everywhere.
export NVM_DIR="$HOME/.nvm"
export NVM_SYMLINK_CURRENT=true
case ":$PATH:" in
  *":$NVM_DIR/current/bin:"*) ;;
  *) [ -d "$NVM_DIR/current/bin" ] && export PATH="$NVM_DIR/current/bin:$PATH" ;;
esac
