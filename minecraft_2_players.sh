#!/bin/bash

# --- Configuration ---

# Your PolyMC user names and instance names
POLYMC_USER1_NAME="User1"
POLYMC_USER2_NAME="User2"
POLYMC_INSTANCE1_NAME="Instance1" # e.g., "1.20.1_Forge"
POLYMC_INSTANCE2_NAME="Instance2" # e.g., "1.19.4_Fabric"

# Assuming you launch PolyMC through Flatpak, otherwise adjust
FLATPAK_CMD="/usr/bin/flatpak"
POLYMC_ID="org.polymc.PolyMC"

# Arguments for launching each PolyMC instance.
# These are now arrays for safer execution.
# Ensure the instance names (-l option) are exactly as configured in PolyMC.
POLYMC_LAUNCH_ARGS_1=(--branch=stable --arch=x86_64 --command=polymc "${POLYMC_ID}" -a "${POLYMC_USER1_NAME}" -l "${POLYMC_INSTANCE1_NAME}")
POLYMC_LAUNCH_ARGS_2=(--branch=stable --arch=x86_64 --command=polymc "${POLYMC_ID}" -a "${POLYMC_USER2_NAME}" -l "${POLYMC_INSTANCE2_NAME}")

# Window Title Fragments for initial identification.
# Minecraft window titles can be complex (e.g., "Minecraft* 1.20.1 - Modded").
# Provide one or two fragments that reliably appear in BOTH instance windows BEFORE renaming.
# STABLE_TITLE_FRAGMENT_PRIMARY: e.g., "Minecraft" or "NeoForge" or "Fabric"
# STABLE_TITLE_FRAGMENT_SECONDARY: e.g., a version number like "1.20" or part of it. Leave blank if one fragment is enough.
STABLE_TITLE_FRAGMENT_PRIMARY="NeoForge" # ADJUST THIS!
STABLE_TITLE_FRAGMENT_SECONDARY="1.21.5"  # ADJUST THIS or leave blank: ""

# Renames the window titles when split-screening
RENAMED_TITLE_1="PolyMC Game - ${POLYMC_USER1_NAME} Split"
RENAMED_TITLE_2="PolyMC Game - ${POLYMC_USER2_NAME} Split"

# Timing Configuration (Adjust if needed)
INITIAL_LAUNCH_WAIT=3             # Time (seconds) after launching BOTH instances before starting to search for windows.
POST_RENAME_WAIT=0.2              # Shorter wait after renaming.
WINDOW_FIND_ATTEMPTS=100          # Max attempts to find a window (100 * 0.2s = 20s max search time per window).
WINDOW_FIND_DELAY=0.2             # Delay between find attempts.
WINDOW_MANIP_DELAY_SHORT=0.1      # Short delay for wmctrl actions.
WINDOW_MANIP_DELAY_NORMAL=0.2     # Normal delay for wmctrl actions in retry path.

# Monitor Configuration (find the Output name through `kscreen-doctor -o` or `xrandr`)
KNOWN_PRIMARY_MONITOR_NAME="HDMI-A-1" # VERIFY this is correct!
# Alternatively, if the name changes but geometry is unique (less common for primary):
# KNOWN_PRIMARY_MONITOR_GEOMETRY_SUBSTRING="5568x3132+2560+0"

# --- HDR Management ---
# HDR_ORIGINAL_STATE="" # Currently unused, but kept for potential future enhancement

disable_hdr() {
    if [ -z "$KNOWN_PRIMARY_MONITOR_NAME" ]; then
        echo "WARNING: KNOWN_PRIMARY_MONITOR_NAME is not set. Cannot manage HDR." >&2
        return
    fi
    echo "INFO: Attempting to disable HDR on $KNOWN_PRIMARY_MONITOR_NAME..." >&2
    if kscreen-doctor "output.${KNOWN_PRIMARY_MONITOR_NAME}.hdr.disable"; then
        echo "INFO: HDR disable command sent." >&2
    else
        echo "WARNING: Failed to send HDR disable command. HDR might still be on." >&2
    fi
    sleep 1 # Give a moment for the display mode to change
}

enable_hdr() {
    if [ -z "$KNOWN_PRIMARY_MONITOR_NAME" ]; then
        echo "WARNING: KNOWN_PRIMARY_MONITOR_NAME is not set. Cannot manage HDR." >&2
        return
    fi
    echo "INFO: Attempting to re-enable HDR on $KNOWN_PRIMARY_MONITOR_NAME..." >&2
    if kscreen-doctor "output.${KNOWN_PRIMARY_MONITOR_NAME}.hdr.enable"; then
        echo "INFO: HDR re-enable command sent." >&2
    else
        echo "WARNING: Failed to send HDR re-enable command." >&2
    fi
}

# --- Script Setup ---
LOG_FILE="/tmp/polymc_splitscreen_launcher.log"
>"$LOG_FILE" # Clear log file at start
exec >>"$LOG_FILE" 2>&1 # Redirect script's stdout and stderr to log file
echo "--- Script started at $(date) ---"

cleanup_and_exit() {
    local reason="$1"
    echo "ERROR: $reason" >&2
    # Attempt to kill PIDs if they were captured and are running
    if [ -n "$LAUNCHER_PID1" ] && ps -p "$LAUNCHER_PID1" > /dev/null; then
        echo "INFO: cleanup_and_exit attempting to kill LAUNCHER_PID1 ($LAUNCHER_PID1)" >&2
        kill "$LAUNCHER_PID1" 2>/dev/null; sleep 0.1; kill -9 "$LAUNCHER_PID1" 2>/dev/null
    fi
    if [ -n "$LAUNCHER_PID2" ] && ps -p "$LAUNCHER_PID2" > /dev/null; then
        echo "INFO: cleanup_and_exit attempting to kill LAUNCHER_PID2 ($LAUNCHER_PID2)" >&2
        kill "$LAUNCHER_PID2" 2>/dev/null; sleep 0.1; kill -9 "$LAUNCHER_PID2" 2>/dev/null
    fi
    enable_hdr # Try to restore HDR
    echo "--- Script exited due to error at $(date) ---" >&2
    exit 1
}
trap 'enable_hdr; echo "--- Script interrupted at $(date) ---" >&2' EXIT SIGINT SIGTERM

# Function to get window ID by *multiple* Title Fragments.
get_window_id_by_title_fragments() {
    local search_label="$1"; local exclude_wid="$2"; shift 2; local title_fragments_to_match=("$@")
    local actual_fragments=()
    # Filter out empty fragments
    for frag in "${title_fragments_to_match[@]}"; do
        [ -n "$frag" ] && actual_fragments+=("$frag")
    done

    if [ ${#actual_fragments[@]} -eq 0 ]; then
        echo "ERROR ($search_label): No valid title fragments provided for search." >&2
        return 1
    fi

    local found_wid=""; local attempt_num=0
    echo "INFO ($search_label): Searching for window matching ALL fragments: [${actual_fragments[*]}] , Exclude WID: '$exclude_wid'" >&2

    while [ -z "$found_wid" ] && [ "$attempt_num" -lt "$WINDOW_FIND_ATTEMPTS" ]; do
        local full_list
        full_list=$(wmctrl -l)
        if [ $? -ne 0 ]; then
            echo "WARNING ($search_label): wmctrl -l failed on attempt $((attempt_num + 1)). Retrying..." >&2
            sleep "$WINDOW_FIND_DELAY"
            attempt_num=$((attempt_num + 1))
            continue
        fi

        local filtered_list="$full_list"
        for frag in "${actual_fragments[@]}"; do
            if [ -z "$filtered_list" ]; then break; fi # No need to continue if previous grep yielded nothing
            filtered_list=$(echo "$filtered_list" | grep -iF -- "$frag")
        done
        
        local candidate_wid=""
        if [ -n "$filtered_list" ]; then
            if [ -n "$exclude_wid" ] && [[ "$exclude_wid" =~ ^0x[0-9a-fA-F]+$ ]]; then
                filtered_list=$(echo "$filtered_list" | grep -v "^${exclude_wid} ") # Exclude by WID at start of line
            fi
            candidate_wid=$(echo "$filtered_list" | awk '{print $1}' | head -n1)
        fi
        
        if [ -n "$candidate_wid" ]; then
            if [[ "$candidate_wid" =~ ^0x[0-9a-fA-F]+$ ]]; then
                echo "INFO ($search_label): Found WID $candidate_wid after $((attempt_num + 1)) attempts." >&2
                found_wid="$candidate_wid"
                break
            else
                echo "WARNING ($search_label): Candidate '$candidate_wid' from filtered list is not a valid WID." >&2
            fi
        fi
        
        if [ -z "$found_wid" ]; then
            if [ $attempt_num -eq 0 ] || [ $(( (attempt_num + 1) % 25 )) -eq 0 ]; then # Log every 25 attempts (e.g. every 5s if delay is 0.2s)
                echo "DEBUG ($search_label): Window not yet found (Attempt $((attempt_num + 1))). Matching windows:" >&2
                echo "${filtered_list:-No windows matched current fragments}" >&2
            fi
            sleep "$WINDOW_FIND_DELAY"
        fi
        attempt_num=$((attempt_num + 1))
    done
    
    if [ -n "$found_wid" ]; then
        echo "$found_wid"
        return 0
    else
        echo "ERROR ($search_label): Could not find window after $WINDOW_FIND_ATTEMPTS attempts." >&2
        return 1
    fi
}

# --- Main Logic ---
disable_hdr

LAUNCHER_PID1=""
LAUNCHER_PID2=""
WID1=""
WID2=""

echo "INFO: Launching PolyMC instance 1 (${POLYMC_USER1_NAME} / ${POLYMC_INSTANCE1_NAME}) in background..." >&2
"$FLATPAK_CMD" run "${POLYMC_LAUNCH_ARGS_1[@]}" >/dev/null 2>&1 &
LAUNCHER_PID1=$!
echo "INFO: PolyMC instance 1 (flatpak PID $LAUNCHER_PID1) launched." >&2

echo "INFO: Launching PolyMC instance 2 (${POLYMC_USER2_NAME} / ${POLYMC_INSTANCE2_NAME}) in background..." >&2
"$FLATPAK_CMD" run "${POLYMC_LAUNCH_ARGS_2[@]}" >/dev/null 2>&1 &
LAUNCHER_PID2=$!
echo "INFO: PolyMC instance 2 (flatpak PID $LAUNCHER_PID2) launched." >&2

echo "INFO: Initial wait: ${INITIAL_LAUNCH_WAIT}s for windows to appear before intensive search..." >&2
sleep "$INITIAL_LAUNCH_WAIT"

# --- Now find WID1 ---
echo "INFO: Attempting to find WID for Instance 1..." >&2
WID1_OUTPUT=$(get_window_id_by_title_fragments "Instance1_Search" "" "$STABLE_TITLE_FRAGMENT_PRIMARY" "$STABLE_TITLE_FRAGMENT_SECONDARY")
WID1_RET=$? 
WID1="$WID1_OUTPUT"

if [ $WID1_RET -ne 0 ] || [ -z "$WID1" ]; then
    cleanup_and_exit "Could not find window for Instance 1 (PID $LAUNCHER_PID1). Fragments: '$STABLE_TITLE_FRAGMENT_PRIMARY', '$STABLE_TITLE_FRAGMENT_SECONDARY'."
fi
echo "INFO: Found WID1: $WID1. Renaming its title to '$RENAMED_TITLE_1'." >&2
wmctrl -i -r "$WID1" -N "$RENAMED_TITLE_1"
if [ $? -ne 0 ]; then echo "WARNING: Failed to rename WID1 ($WID1). This might cause issues finding WID2." >&2; fi
sleep "$POST_RENAME_WAIT" 

# --- Then find WID2 (excluding WID1) ---
echo "INFO: Attempting to find WID for Instance 2 (excluding WID1: $WID1)..." >&2
WID2_OUTPUT=$(get_window_id_by_title_fragments "Instance2_Search" "$WID1" "$STABLE_TITLE_FRAGMENT_PRIMARY" "$STABLE_TITLE_FRAGMENT_SECONDARY")
WID2_RET=$?
WID2="$WID2_OUTPUT"

if [ $WID2_RET -ne 0 ] || [ -z "$WID2" ]; then
    cleanup_and_exit "Could not find window for Instance 2 (PID $LAUNCHER_PID2). Fragments: '$STABLE_TITLE_FRAGMENT_PRIMARY', '$STABLE_TITLE_FRAGMENT_SECONDARY'."
fi
if [ "$WID1" == "$WID2" ]; then
    cleanup_and_exit "WID1 and WID2 are the same ($WID1), which is unexpected after renaming WID1."
fi
echo "INFO: Found WID2: $WID2. Renaming its title to '$RENAMED_TITLE_2'." >&2
wmctrl -i -r "$WID2" -N "$RENAMED_TITLE_2"
if [ $? -ne 0 ]; then echo "WARNING: Failed to rename WID2 ($WID2)." >&2; fi
sleep "$POST_RENAME_WAIT"

echo "INFO: Successfully identified WID1: $WID1 ('$RENAMED_TITLE_1') and WID2: $WID2 ('$RENAMED_TITLE_2')" >&2

# --- Screen Dimension Parsing ---
PRIMARY_WIDTH=""; PRIMARY_HEIGHT=""; PRIMARY_OFFSET_X=""; PRIMARY_OFFSET_Y=""
MONITOR_INFO_SOURCE="Unknown"

echo "INFO: --- Starting Screen Dimension Parsing ---" >&2
XRANDR_OUTPUT=$(xrandr --query)
# For debugging, uncomment next lines:
# echo "DEBUG: Full xrandr --query output:" >&2
# echo "$XRANDR_OUTPUT" >&2
# echo "------------------------------------------" >&2

# Attempt 0: Look for a specific, known primary monitor by its name
if [ -n "$KNOWN_PRIMARY_MONITOR_NAME" ]; then
    echo "INFO: Attempt 0: Looking for known primary monitor by name: '$KNOWN_PRIMARY_MONITOR_NAME'" >&2
    KNOWN_PRIMARY_LINE=$(echo "$XRANDR_OUTPUT" | grep "^${KNOWN_PRIMARY_MONITOR_NAME} connected [0-9]*x[0-9]*+[0-9]*+[0-9]*")
    if [ -n "$KNOWN_PRIMARY_LINE" ]; then
        echo "INFO: Found line matching known primary name '$KNOWN_PRIMARY_MONITOR_NAME': $KNOWN_PRIMARY_LINE" >&2
        if [[ "$KNOWN_PRIMARY_LINE" =~ ([0-9]+x[0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
            DIMENSIONS_STR="${BASH_REMATCH[1]}"; PRIMARY_OFFSET_X="${BASH_REMATCH[2]}"; PRIMARY_OFFSET_Y="${BASH_REMATCH[3]}"
            PRIMARY_WIDTH=$(echo "$DIMENSIONS_STR" | cut -dx -f1); PRIMARY_HEIGHT=$(echo "$DIMENSIONS_STR" | cut -dx -f2)
            MONITOR_INFO_SOURCE="xrandr (known name: $KNOWN_PRIMARY_MONITOR_NAME)"
            echo "INFO: Parsed from known primary: W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
        else
            echo "WARNING: Known primary name line found, but regex failed to parse geometry." >&2; KNOWN_PRIMARY_LINE=""
        fi
    else
        echo "INFO: No line found matching known primary name '$KNOWN_PRIMARY_MONITOR_NAME' with connected geometry." >&2
    fi
# elif [ -n "$KNOWN_PRIMARY_MONITOR_GEOMETRY_SUBSTRING" ]; then # Optional: add logic for geometry substring
    # echo "INFO: Attempt 0b: Looking for known primary by geometry substring '$KNOWN_PRIMARY_MONITOR_GEOMETRY_SUBSTRING'" >&2
    # ... implement if needed ...
fi

# Attempt 1: Find line explicitly containing ' connected primary'
if [ -z "$PRIMARY_WIDTH" ]; then
    echo "INFO: Attempt 1: Looking for 'connected primary' keyword..." >&2
    PRIMARY_LINE=$(echo "$XRANDR_OUTPUT" | grep ' connected primary')
    if [ -n "$PRIMARY_LINE" ]; then
        echo "INFO: Found line with ' connected primary': $PRIMARY_LINE" >&2
        if [[ "$PRIMARY_LINE" =~ ([0-9]+x[0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
            DIMENSIONS_STR="${BASH_REMATCH[1]}"; PRIMARY_OFFSET_X="${BASH_REMATCH[2]}"; PRIMARY_OFFSET_Y="${BASH_REMATCH[3]}"
            PRIMARY_WIDTH=$(echo "$DIMENSIONS_STR" | cut -dx -f1); PRIMARY_HEIGHT=$(echo "$DIMENSIONS_STR" | cut -dx -f2)
            MONITOR_INFO_SOURCE="xrandr (explicit 'connected primary')"
            echo "INFO: Parsed from 'connected primary': W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
        else
            echo "WARNING: 'connected primary' line found, but regex failed to parse geometry." >&2; PRIMARY_LINE=""
        fi
    else
        echo "INFO: No line found with ' connected primary'." >&2
    fi
fi

# Attempt 2: If still no specific primary, find the first 'connected' non-virtual monitor with geometry
if [ -z "$PRIMARY_WIDTH" ]; then
    echo "INFO: Attempt 2: Looking for first 'connected' active monitor (heuristic)..." >&2
    FIRST_CONNECTED_ACTIVE_LINE=$(echo "$XRANDR_OUTPUT" | grep ' connected [0-9]*x[0-9]*+[0-9]*+[0-9]*' | grep -v 'disconnected' | grep -Ev 'None-|VIRTUAL|Screen[0-9]' | head -n1)
    if [ -n "$FIRST_CONNECTED_ACTIVE_LINE" ]; then
        echo "INFO: Using first 'connected' line with geometry: $FIRST_CONNECTED_ACTIVE_LINE" >&2
        if [[ "$FIRST_CONNECTED_ACTIVE_LINE" =~ ([0-9]+x[0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
            DIMENSIONS_STR="${BASH_REMATCH[1]}"; PRIMARY_OFFSET_X="${BASH_REMATCH[2]}"; PRIMARY_OFFSET_Y="${BASH_REMATCH[3]}"
            PRIMARY_WIDTH=$(echo "$DIMENSIONS_STR" | cut -dx -f1); PRIMARY_HEIGHT=$(echo "$DIMENSIONS_STR" | cut -dx -f2)
            MONITOR_INFO_SOURCE="xrandr (first connected with geometry heuristic)"
            echo "INFO: Parsed from heuristic: W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
        else
            echo "WARNING: Found first 'connected' line with geometry, but regex failed: $FIRST_CONNECTED_ACTIVE_LINE" >&2
        fi
    else
        echo "INFO: No 'connected' line with parseable geometry found as a fallback heuristic." >&2
    fi
fi

# Attempt 3: Fallback to xdpyinfo (usually full desktop area, offset becomes 0,0)
if [ -z "$PRIMARY_WIDTH" ]; then
    echo "WARNING: Attempt 3: All xrandr parsing attempts failed. Falling back to xdpyinfo." >&2
    XDPY_DIMENSIONS=$(xdpyinfo | grep dimensions | sed -r 's/^[^0-9]*([0-9]+x[0-9]+).*$/\1/')
    if [ -n "$XDPY_DIMENSIONS" ]; then
        PRIMARY_WIDTH=$(echo "$XDPY_DIMENSIONS" | cut -dx -f1); PRIMARY_HEIGHT=$(echo "$XDPY_DIMENSIONS" | cut -dx -f2)
        PRIMARY_OFFSET_X=0; PRIMARY_OFFSET_Y=0 # xdpyinfo generally gives total screen, so offset 0,0 for primary
        MONITOR_INFO_SOURCE="xdpyinfo (full desktop fallback)"
        echo "INFO: Using xdpyinfo: W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
    fi
fi

if ! [[ "$PRIMARY_WIDTH" =~ ^[0-9]+$ && "$PRIMARY_HEIGHT" =~ ^[0-9]+$ && "$PRIMARY_OFFSET_X" =~ ^[0-9]+$ && "$PRIMARY_OFFSET_Y" =~ ^[0-9]+$ ]]; then
    cleanup_and_exit "Could not reliably determine screen dimensions/offsets. Final Source: $MONITOR_INFO_SOURCE. Parsed: W='$PRIMARY_WIDTH', H='$PRIMARY_HEIGHT', X='$PRIMARY_OFFSET_X', Y='$PRIMARY_OFFSET_Y'"
fi
echo "INFO: FINAL Using screen area for split ($MONITOR_INFO_SOURCE): W=${PRIMARY_WIDTH}, H=${PRIMARY_HEIGHT} at offset X=${PRIMARY_OFFSET_X}, Y=${PRIMARY_OFFSET_Y}" >&2

# Target sizes and positions
TARGET_W1=$((PRIMARY_WIDTH / 2))
TARGET_W2=$((PRIMARY_WIDTH - TARGET_W1)) # Ensures full width coverage if primary_width is odd
POS_X1=$PRIMARY_OFFSET_X
POS_Y1=$PRIMARY_OFFSET_Y
SIZE_W1=$TARGET_W1
SIZE_H1=$PRIMARY_HEIGHT

POS_X2=$((PRIMARY_OFFSET_X + TARGET_W1))
POS_Y2=$PRIMARY_OFFSET_Y
SIZE_W2=$TARGET_W2
SIZE_H2=$PRIMARY_HEIGHT

# --- Window Management Function ---
manage_window() {
    local WID="$1"; local TARGET_X="$2"; local TARGET_Y="$3"; local TARGET_W="$4"; local TARGET_H="$5"; local W_NAME="$6"
    echo "INFO ($W_NAME): Managing window $WID. Target: X=$TARGET_X, Y=$TARGET_Y, W=$TARGET_W, H=$TARGET_H" >&2
    if [ -z "$WID" ]; then echo "ERROR ($W_NAME): Window ID is empty." >&2; return 1; fi

    echo "INFO ($W_NAME): Activating and normalizing $WID." >&2
    wmctrl -i -a "$WID"; sleep "$WINDOW_MANIP_DELAY_SHORT"
    wmctrl -i -r "$WID" -b remove,fullscreen; sleep "$WINDOW_MANIP_DELAY_SHORT"
    wmctrl -i -r "$WID" -b remove,maximized_vert,maximized_horz; sleep "$WINDOW_MANIP_DELAY_SHORT"

    echo "INFO ($W_NAME): Attempting to move/resize $WID." >&2
    wmctrl -i -r "$WID" -e "0,${TARGET_X},${TARGET_Y},${TARGET_W},${TARGET_H}"
    local ret_resize=$?

    if [ $ret_resize -ne 0 ]; then
        echo "WARNING ($W_NAME): Initial resize/move failed (code $ret_resize). Retrying..." >&2
        wmctrl -i -a "$WID"; sleep "$WINDOW_MANIP_DELAY_SHORT" # Re-activate
        wmctrl -i -r "$WID" -b remove,fullscreen; sleep "$WINDOW_MANIP_DELAY_NORMAL" # Longer pause for retry
        wmctrl -i -r "$WID" -b remove,maximized_vert,maximized_horz; sleep "$WINDOW_MANIP_DELAY_NORMAL"
        echo "INFO ($W_NAME): Retrying move/resize $WID." >&2
        wmctrl -i -r "$WID" -e "0,${TARGET_X},${TARGET_Y},${TARGET_W},${TARGET_H}"
        if [ $? -ne 0 ]; then echo "ERROR ($W_NAME): Retry of resize/move for $WID also failed." >&2; else echo "INFO ($W_NAME): Retry resize/move for $WID successful." >&2; fi
    else
        echo "INFO ($W_NAME): Initial resize/move for $WID successful." >&2
    fi
    sleep "$WINDOW_MANIP_DELAY_SHORT" # Final settle
}

echo "INFO: Managing WID1 ($WID1) - ${RENAMED_TITLE_1} - placing on RIGHT" >&2
manage_window "$WID1" "$POS_X2" "$POS_Y2" "$SIZE_W2" "$SIZE_H2" "WID1_Right"

echo "INFO: Managing WID2 ($WID2) - ${RENAMED_TITLE_2} - placing on LEFT" >&2
manage_window "$WID2" "$POS_X1" "$POS_Y1" "$SIZE_W1" "$SIZE_H1" "WID2_Left"

echo "INFO: Activating WID1 (${RENAMED_TITLE_1}, right-side window) for input focus." >&2
wmctrl -i -a "$WID1" # Or WID2 if you prefer left to have focus first

echo "INFO: Window positioning complete. Script will now monitor game windows WID1 ($WID1) and WID2 ($WID2) and exit when both are closed." >&2

window_exists() {
    local wid_to_check="$1"
    if [ -z "$wid_to_check" ]; then return 1; fi
    wmctrl -l | grep -q "^${wid_to_check} "
    return $?
}

while ( [ -n "$WID1" ] && window_exists "$WID1" ) || ( [ -n "$WID2" ] && window_exists "$WID2" ); do
    current_runtime_seconds=$(ps -o etimes= -p $$ || echo 0) # ps can fail if script is very short-lived, default to 0
    if [[ "$current_runtime_seconds" -lt 60 ]]; then
        sleep 1 # Check every 1 second for the first minute
    else
        sleep 3 # Check every 3 seconds thereafter
    fi
done

echo "INFO: Both game windows WID1 ($WID1) and WID2 ($WID2) appear to have closed." >&2

# Optional: Attempt to clean up the original flatpak PIDs if they are still somehow running
if [ -n "$LAUNCHER_PID1" ] && ps -p "$LAUNCHER_PID1" > /dev/null; then
    echo "INFO: Attempting to ensure original flatpak process LAUNCHER_PID1 ($LAUNCHER_PID1) is terminated." >&2
    kill "$LAUNCHER_PID1" 2>/dev/null; sleep 0.1; kill -9 "$LAUNCHER_PID1" 2>/dev/null
fi
if [ -n "$LAUNCHER_PID2" ] && ps -p "$LAUNCHER_PID2" > /dev/null; then
    echo "INFO: Attempting to ensure original flatpak process LAUNCHER_PID2 ($LAUNCHER_PID2) is terminated." >&2
    kill "$LAUNCHER_PID2" 2>/dev/null; sleep 0.1; kill -9 "$LAUNCHER_PID2" 2>/dev/null
fi

echo "INFO: Script finished." >&2
# Trap will call enable_hdr
exit 0
