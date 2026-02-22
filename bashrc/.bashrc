# If not running interactively, don't do anything (leave this at the top of this file)
[[ $- != *i* ]] && return

# All the default Omarchy aliases and functions
# (don't mess with these directly, just overwrite them here!)
source ~/.local/share/omarchy/default/bash/rc

# Add your own exports, aliases, and functions here.
alias haxx='omarchy-launch-screensaver'
alias ol='ollama'
alias la='ls -la'
alias vi='nvim'
alias fab='fabric-ai'

# Make an alias for invoking commands you use constantly
# alias p='python'
. "$HOME/.cargo/env"

alias pbcopy='wl-copy --type text/plain --trim-newline'
alias pbpaste='wl-paste --type text/plain'
export TMPDIR="$HOME/.tmp"

# Golang environment variables
export GOROOT=/usr/local/go
export GOPATH=$HOME/go

# Update PATH to include GOPATH and GOROOT binaries
export PATH=$GOPATH/bin:$GOROOT/bin:$HOME/.local/bin:$PATH

alias gpu-check-reset='ldr-gpu-passthrough info needs-reset && echo "⚠️  Reset Bug: YES" || echo "✅ Reset Bug: NO"'
alias gpu-check-health='ldr-gpu-passthrough info gpu-health && echo "✅ Health: OK" || echo "❌ Health: ERROR"'
alias gpu-check-persist='ldr-gpu-passthrough info is-persistent && echo "💾 Persistent: YES" || echo "⏳ Persistent: NO"'
export LDR_VM_IGNORE_GPU_HEALTH=1

. "$HOME/.local/share/../bin/env"
