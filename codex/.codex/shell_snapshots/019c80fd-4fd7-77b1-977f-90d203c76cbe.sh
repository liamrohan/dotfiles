# Snapshot file
# Unset all aliases to avoid conflicts with functions
# Functions
__systemd_osc_context_common () 
{ 
    if [ -f /etc/machine-id ]; then
        printf ";machineid=%s" "$(< /etc/machine-id)";
    fi;
    printf ";user=%s;hostname=%s;bootid=%s;pid=%s" "$USER" "$HOSTNAME" "$(< /proc/sys/kernel/random/boot_id)" "$$"
}
__systemd_osc_context_escape () 
{ 
    echo "$1" | sed -e 's/\\/\\x5x/g' -e 's/;/\\x3b/g'
}
__systemd_osc_context_precmdline () 
{ 
    local systemd_exitstatus="$?";
    if [ -n "${systemd_osc_context_cmd_id:-}" ]; then
        if [ "$systemd_exitstatus" -ge 127 ]; then
            printf "\033]3008;end=%s;exit=interrupt;signal=%s\033\\" "$systemd_osc_context_cmd_id" $((systemd_exitstatus-127));
        else
            if [ "$systemd_exitstatus" -ne 0 ]; then
                printf "\033]3008;end=%s;exit=failure;status=%s\033\\" "$systemd_osc_context_cmd_id" $((systemd_exitstatus));
            else
                printf "\033]3008;end=%s;exit=success\033\\" "$systemd_osc_context_cmd_id";
            fi;
        fi;
    fi;
    if [ -z "${systemd_osc_context_shell_id:-}" ]; then
        read -r systemd_osc_context_shell_id < /proc/sys/kernel/random/uuid;
    fi;
    printf "\033]3008;start=%s%s;type=shell;cwd=%s\033\\" "$systemd_osc_context_shell_id" "$(__systemd_osc_context_common)" "$(__systemd_osc_context_escape "$PWD")";
    read -r systemd_osc_context_cmd_id < /proc/sys/kernel/random/uuid
}
__systemd_osc_context_ps0 () 
{ 
    [ -n "${systemd_osc_context_cmd_id:-}" ] || return;
    printf "\033]3008;start=%s%s;type=command;cwd=%s\033\\" "$systemd_osc_context_cmd_id" "$(__systemd_osc_context_common)" "$(__systemd_osc_context_escape "$PWD")"
}
gawklibpath_append () 
{ 
    [ -z "$AWKLIBPATH" ] && AWKLIBPATH=`gawk 'BEGIN {print ENVIRON["AWKLIBPATH"]}'`;
    export AWKLIBPATH="$AWKLIBPATH:$*"
}
gawklibpath_default () 
{ 
    unset AWKLIBPATH;
    export AWKLIBPATH=`gawk 'BEGIN {print ENVIRON["AWKLIBPATH"]}'`
}
gawklibpath_prepend () 
{ 
    [ -z "$AWKLIBPATH" ] && AWKLIBPATH=`gawk 'BEGIN {print ENVIRON["AWKLIBPATH"]}'`;
    export AWKLIBPATH="$*:$AWKLIBPATH"
}
gawkpath_append () 
{ 
    [ -z "$AWKPATH" ] && AWKPATH=`gawk 'BEGIN {print ENVIRON["AWKPATH"]}'`;
    export AWKPATH="$AWKPATH:$*"
}
gawkpath_default () 
{ 
    unset AWKPATH;
    export AWKPATH=`gawk 'BEGIN {print ENVIRON["AWKPATH"]}'`
}
gawkpath_prepend () 
{ 
    [ -z "$AWKPATH" ] && AWKPATH=`gawk 'BEGIN {print ENVIRON["AWKPATH"]}'`;
    export AWKPATH="$*:$AWKPATH"
}

# setopts 3
set -o braceexpand
set -o hashall
set -o interactive-comments

# aliases 0

# exports 103
declare -x ALACRITTY_LOG="/tmp/Alacritty-2573.log"
declare -x ALACRITTY_SOCKET="/run/user/1000/Alacritty-wayland-1-2573.sock"
declare -x ALACRITTY_WINDOW_ID="94875083481824"
declare -x BAT_THEME="ansi"
declare -x BROWSER="chromium"
declare -x COLORTERM="truecolor"
declare -x CUDA_PATH="/opt/cuda"
declare -x DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/1000/bus"
declare -x DEBUGINFOD_URLS="https://debuginfod.archlinux.org "
declare -x DESKTOP_SESSION="hyprland-uwsm"
declare -x DISPLAY=":1"
declare -x EDITOR="nvim"
declare -x ELECTRON_OZONE_PLATFORM_HINT="wayland"
declare -x GDK_BACKEND="wayland,x11,*"
declare -x GDK_SCALE="1.75"
declare -x GOPATH="/home/ldr-cavetroll/go"
declare -x GOROOT="/usr/local/go"
declare -x GUM_CONFIRM_PROMPT_FOREGROUND="6"
declare -x GUM_CONFIRM_SELECTED_BACKGROUND="2"
declare -x GUM_CONFIRM_SELECTED_FOREGROUND="0"
declare -x GUM_CONFIRM_UNSELECTED_BACKGROUND="8"
declare -x GUM_CONFIRM_UNSELECTED_FOREGROUND="0"
declare -x HL_INITIAL_WORKSPACE_TOKEN="286190fb-ea3d-4d09-98a7-8282050a02f8"
declare -x HOME="/home/ldr-cavetroll"
declare -x HYPRCURSOR_SIZE="24"
declare -x HYPRLAND_CMD="Hyprland --watchdog-fd 4"
declare -x HYPRLAND_INSTANCE_SIGNATURE="dd220efe7b1e292415bd0ea7161f63df9c95bfd3_1771690389_180816073"
declare -x INPUT_METHOD="fcitx"
declare -x INVOCATION_ID="e572c983b8cd4044888b3478e34f4e55"
declare -x JOURNAL_STREAM="9:22089"
declare -x LANG="en_US.UTF-8"
declare -x LANGUAGE
declare -x LC_ADDRESS
declare -x LC_COLLATE
declare -x LC_CTYPE
declare -x LC_IDENTIFICATION
declare -x LC_MEASUREMENT
declare -x LC_MESSAGES
declare -x LC_MONETARY
declare -x LC_NAME
declare -x LC_NUMERIC
declare -x LC_PAPER
declare -x LC_TELEPHONE
declare -x LC_TIME
declare -x LDR_VM_IGNORE_GPU_HEALTH="1"
declare -x LOGNAME="ldr-cavetroll"
declare -x MAIL="/var/spool/mail/ldr-cavetroll"
declare -x MANAGERPID="1477"
declare -x MANAGERPIDFDID="1478"
declare -x MEMORY_PRESSURE_WATCH="/sys/fs/cgroup/user.slice/user-1000.slice/user@1000.service/session.slice/wayland-wm@hyprland.desktop.service/memory.pressure"
declare -x MEMORY_PRESSURE_WRITE="c29tZSAyMDAwMDAgMjAwMDAwMAA="
declare -x MISE_SHELL="bash"
declare -x MOTD_SHOWN="pam"
declare -x MOZ_ENABLE_WAYLAND="1"
declare -x NOTIFY_SOCKET="/run/user/1000/systemd/notify"
declare -x NVCC_CCBIN="/usr/bin/g++"
declare -x OMARCHY_PATH="/home/ldr-cavetroll/.local/share/omarchy"
declare -x OZONE_PLATFORM="wayland"
declare -x PATH="/home/ldr-cavetroll/.codex/tmp/arg0/codex-arg0CPc2PW:/home/ldr-cavetroll/go/bin:/usr/local/go/bin:/home/ldr-cavetroll/.local/bin:/home/ldr-cavetroll/.cargo/bin:/home/ldr-cavetroll/.local/share/omarchy/bin/:/usr/local/sbin:/usr/local/bin:/usr/bin:/opt/cuda/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"
declare -x QT_IM_MODULE="fcitx"
declare -x QT_QPA_PLATFORM="wayland;xcb"
declare -x QT_STYLE_OVERRIDE="kvantum"
declare -x SDL_IM_MODULE="fcitx"
declare -x SDL_VIDEODRIVER="wayland"
declare -x SHELL="/usr/bin/bash"
declare -x SHLVL="2"
declare -x STARSHIP_SESSION_KEY="6233367122813236"
declare -x STARSHIP_SHELL="bash"
declare -x SUDO_EDITOR="nvim"
declare -x SYSTEMD_EXEC_PID="1705"
declare -x TERM="xterm-256color"
declare -x TERMINAL="xdg-terminal-exec"
declare -x TMPDIR="/home/ldr-cavetroll/.tmp"
declare -x USER="ldr-cavetroll"
declare -x UWSM_FINALIZE_VARNAMES="HYPRLAND_INSTANCE_SIGNATURE HYPRLAND_CMD HYPRCURSOR_THEME HYPRCURSOR_SIZE XCURSOR_SIZE XCURSOR_THEME"
declare -x UWSM_WAIT_VARNAMES="HYPRLAND_INSTANCE_SIGNATURE"
declare -x WAYLAND_DISPLAY="wayland-1"
declare -x WINDOWID="94875083481824"
declare -x XCOMPOSEFILE="~/.XCompose"
declare -x XCURSOR_SIZE="24"
declare -x XDG_BACKEND="wayland"
declare -x XDG_CACHE_HOME="/home/ldr-cavetroll/.cache"
declare -x XDG_CONFIG_DIRS="/etc/xdg"
declare -x XDG_CONFIG_HOME="/home/ldr-cavetroll/.config"
declare -x XDG_CURRENT_DESKTOP="Hyprland"
declare -x XDG_DATA_DIRS="/usr/local/share:/usr/share"
declare -x XDG_DATA_HOME="/home/ldr-cavetroll/.local/share"
declare -x XDG_MENU_PREFIX="hyprland-"
declare -x XDG_RUNTIME_DIR="/run/user/1000"
declare -x XDG_SEAT="seat0"
declare -x XDG_SEAT_PATH="/org/freedesktop/DisplayManager/Seat0"
declare -x XDG_SESSION_CLASS="user"
declare -x XDG_SESSION_DESKTOP="Hyprland"
declare -x XDG_SESSION_ID="1"
declare -x XDG_SESSION_PATH="/org/freedesktop/DisplayManager/Session0"
declare -x XDG_SESSION_TYPE="wayland"
declare -x XDG_STATE_HOME="/home/ldr-cavetroll/.local/state"
declare -x XDG_VTNR="1"
declare -x XMODIFIERS="@im=fcitx"
declare -x _JAVA_AWT_WM_NONREPARENTING="1"
declare -x __MISE_DIFF="eAFrXpyfk9KwOC+1vGFJQWJJxgQASssINA"
declare -x __MISE_ORIG_PATH="/home/ldr-cavetroll/.local/share/omarchy/bin/:/usr/local/sbin:/usr/local/bin:/usr/bin:/opt/cuda/bin:/usr/lib/jvm/default/bin:/usr/bin/site_perl:/usr/bin/vendor_perl:/usr/bin/core_perl"
declare -x __MISE_SESSION="eAHrXJOTn5iSmhJfkp+fUzxhHZSXnJ+XlplePGENhBFfkFiSUTxhcWpeWcPyxJzMxOLU4oZVJalFifFpmTmpxRMWp2QW7dXPyM9N1c9JKdJNTixLLSnKz8nR10vJLwErWZOaVxZfllgUn5FYnLEhydjSMDXN1CDJ3DDZ0NTCbG1OYklqcUl8aUFKYknqEQEGOGCc0/C78jUAVEtCMA"
