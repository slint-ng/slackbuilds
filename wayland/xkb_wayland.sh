#!/bin/sh
#
# Export XKB_DEFAULT_* variables for Wayland sessions in Slint.
# Multi-layout, multi-variant, and group-switching compatible.
#

# Initialize empty values
RULES=""
MODEL=""
LAYOUT=""
VARIANT=""
OPTIONS=""

#
# --- CASE 1: X11 is running → read live settings via setxkbmap ---
#
if [ -n "$DISPLAY" ] && command -v setxkbmap >/dev/null 2>&1 ; then
    TMPFILE=$(mktemp /tmp/xkb-wl.XXXXXX)
    if setxkbmap -query >"$TMPFILE" 2>/dev/null && [ -s "$TMPFILE" ]; then
        while IFS= read -r line; do
            case "$line" in
                rules:*)
                    RULES=$(printf '%s\n' "$line" | sed 's/^rules:[[:space:]]*//')
                    ;;
                model:*)
                    MODEL=$(printf '%s\n' "$line" | sed 's/^model:[[:space:]]*//')
                    ;;
                layout:*)
                    LAYOUT=$(printf '%s\n' "$line" | sed 's/^layout:[[:space:]]*//')
                    ;;
                variant:*)
                    VARIANT=$(printf '%s\n' "$line" | sed 's/^variant:[[:space:]]*//')
                    ;;
                options:*)
                    OPTIONS=$(printf '%s\n' "$line" | sed 's/^options:[[:space:]]*//')
                    ;;
            esac
        done <"$TMPFILE"
    fi
    rm -f "$TMPFILE"

#
# --- CASE 2: X11 NOT running → fallback to xorg.conf.d ---
#
elif [ -r /etc/X11/xorg.conf.d/10-keymap.conf ]; then
    CFG=/etc/X11/xorg.conf.d/10-keymap.conf
    while IFS= read -r line; do
        case "$line" in
            *\"XkbRules\"*)
                RULES=$(printf '%s\n' "$line" \
                    | sed 's/.*"XkbRules"[[:space:]]*"\([^"]*\)".*/\1/')
                ;;
            *\"XkbModel\"*)
                MODEL=$(printf '%s\n' "$line" \
                    | sed 's/.*"XkbModel"[[:space:]]*"\([^"]*\)".*/\1/')
                ;;
            *\"XkbLayout\"*)
                LAYOUT=$(printf '%s\n' "$line" \
                    | sed 's/.*"XkbLayout"[[:space:]]*"\([^"]*\)".*/\1/')
                ;;
            *\"XkbVariant\"*)
                VARIANT=$(printf '%s\n' "$line" \
                    | sed 's/.*"XkbVariant"[[:space:]]*"\([^"]*\)".*/\1/')
                ;;
            *\"XkbOptions\"*)
                OPTIONS=$(printf '%s\n' "$line" \
                    | sed 's/.*"XkbOptions"[[:space:]]*"\([^"]*\)".*/\1/')
                ;;
        esac
    done <"$CFG"
fi


#
# ---- Multi-layout + group switching handling ----
#

# X11 sometimes stores XkbOptions space-separated → Wayland requires comma-separated
if [ -n "$OPTIONS" ]; then
    OPTIONS=$(printf '%s\n' "$OPTIONS" | sed 's/[[:space:]]\+/,/g')
fi

# Nothing else needs to be done — libxkbcommon handles:
#   layout="us,fr,de"
#   variant=",,oss"
#   options="grp:alt_shift_toggle,caps:escape"
# exactly as X11 does.


#
# ---- Export for Wayland ----
#

[ -n "$RULES" ]   && export XKB_DEFAULT_RULES="$RULES"
[ -n "$MODEL" ]   && export XKB_DEFAULT_MODEL="$MODEL"
[ -n "$LAYOUT" ]  && export XKB_DEFAULT_LAYOUT="$LAYOUT"
[ -n "$VARIANT" ] && export XKB_DEFAULT_VARIANT="$VARIANT"
[ -n "$OPTIONS" ] && export XKB_DEFAULT_OPTIONS="$OPTIONS"
