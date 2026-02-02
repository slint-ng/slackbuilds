#!/bin/sh
# Cycle focus through visible X windows (next or previous).
# Usage: window_cycle.sh next | prev
# POSIX-compliant; works without a window manager.

# Get direction argument
case "$1" in
    next) DIR="next" ;;
    prev) DIR="prev" ;;
    *)
        echo "Usage: $0 next | prev" >&2
        exit 1
        ;;
esac

# Get all visible window IDs (space-separated)
WINDOWS=$(xdotool search --onlyvisible -class . | tr '\n' ' ')

# Get the currently focused window ID
CURRENT=$(xdotool getwindowfocus)

NEXT=""
PREV=""
LAST=""
FOUND=0

for ID in $WINDOWS; do
    if [ "$DIR" = "next" ]; then
        # Find next window
        if [ "$FOUND" -eq 1 ]; then
            NEXT=$ID
            break
        fi
        if [ "$ID" = "$CURRENT" ]; then
            FOUND=1
        fi
    else
        # Find previous window
        if [ "$ID" = "$CURRENT" ]; then
            if [ -z "$PREV" ]; then
                PREV=$LAST
            fi
            break
        fi
        PREV=$ID
        LAST=$ID
    fi
done

# Wrap around if needed
if [ "$DIR" = "next" ]; then
    if [ -z "$NEXT" ]; then
        for ID in $WINDOWS; do
            NEXT=$ID
            break
        done
    fi
    TARGET=$NEXT
else
    if [ -z "$PREV" ]; then
        for ID in $WINDOWS; do
            PREV=$ID
        done
    fi
    TARGET=$PREV
fi

# Focus the chosen window
xdotool windowfocus "$TARGET"
##
"sleep 0.1 && /path/to/window_cycle.sh next"
  Alt + Tab
############
#.xinirc
#!/bin/sh
# ~/.xinitrc — start your X session without a window manager

# 1. Set environment variables (optional)
# export PATH="$HOME/bin:$PATH"

# 2. Start xbindkeys for Alt+Tab switching
xbindkeys &

# 3. (Optional) Start other background utilities if you need them
# xsetroot -solid black &
# unclutter &       # hide mouse when idle
# xset -dpms s off  # disable screen blanking

# 4. Start your main application(s)
# Example: start an xterm and keep it open
xterm &

# 5. Wait for all background processes
wait


#"The ampersand (&) after xbindkeys lets it run in the background so the rest of .xinitrc continues.

#The wait at the end keeps X running until all programs you started close — this is the usual pattern for bare X setups.

#If your main app is full-screen (e.g., a kiosk, GUI app, or game), you can just launch that last, e.g.:

#/path/to/myapp

# and omit wait.
## 
###Oher version of xinitrc
#!/bin/sh
# ~/.xinitrc — minimal bare-X setup
# POSIX-compliant

# --- 1. Environment setup (optional) ---
# export PATH="$HOME/bin:$PATH"

# --- 2. Background helpers ---
# Start keybindings (Alt+Tab cycling)
xbindkeys &

# Set a simple root window background color
xsetroot -solid black &

# Optional: hide cursor when idle
# unclutter &

# --- 3. Main applications ---
# Start all main apps in background
firefox &
xterm &
gedit &

# Add more main apps here if needed:
# chromium &
# mpv &

# --- 4. Wait for all main apps to exit ---
# This ensures X will close only after all main apps are closed
wait
# or exec mpv then closing mpv will kill X and apps in the background? 
