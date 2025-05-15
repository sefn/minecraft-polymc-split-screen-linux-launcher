#!/bin/bash

# --- Configuration ---

# Your PolyMC user names and instance names
POLYMC_USER1_NAME="User1"
POLYMC_USER2_NAME="User2"
POLYMC_INSTANCE1_NAME="Instance1"
POLYMC_INSTANCE2_NAME="Instance2"

# Assuming you launch PolyMC through Flatpak, otherwise adjust
FLATPAK_CMD="/usr/bin/flatpak"
POLYMC_ID="org.polymc.PolyMC"
POLYMC_ARGS_1="--branch=stable --arch=x86_64 --command=polymc ${POLYMC_ID} -a ${POLYMC_USER1_NAME} -l ${POLYMC_INSTANCE1_NAME} "
POLYMC_ARGS_2="--branch=stable --arch=x86_64 --command=polymc ${POLYMC_ID} -a ${POLYMC_USER2_NAME} -l ${POLYMC_INSTANCE2_NAME} "

# The window title (or part of it) when the game has launched (adjust if the Minecraft window title is different)
PART_OF_WINDOW_TITLE="NeoForge"

# Renames the window titles when split-screening
RENAMED_TITLE_1="PolyMC Game - Instance 1 Split"
RENAMED_TITLE_2="PolyMC Game - Instance 2 Split"

# Timing Configuration (Adjust if needed)
LAUNCH_AND_TITLE_STABILIZE_WAIT=10 # Time for window to appear and title to stabilize
POST_RENAME_WAIT=0.5               # Shorter wait after renaming
WINDOW_FIND_ATTEMPTS=20            # Max attempts to find a window by title
WINDOW_FIND_DELAY=1                # Delay between find attempts
WINDOW_MANIP_DELAY_SHORT=0.3       # Short delay for wmctrl actions in normal path
WINDOW_MANIP_DELAY_NORMAL=0.6      # Normal delay for wmctrl actions in retry path

# Monitor Configuration (find the Output name through kscreen-doctor -o)
KNOWN_PRIMARY_MONITOR_NAME="HDMI-A-1"
# Alternatively, if the name changes but geometry is unique:
# KNOWN_PRIMARY_MONITOR_GEOMETRY_SUBSTRING="5568x3132+2560+0"

# --- HDR Management ---
HDR_ORIGINAL_STATE="" # Variable to store original state if we can query it

# Function to attempt to disable HDR
disable_hdr() {
    echo "INFO: Attempting to disable HDR on $KNOWN_PRIMARY_MONITOR_NAME..." >&2

    if kscreen-doctor output.$KNOWN_PRIMARY_MONITOR_NAME.hdr.disable; then
        echo "INFO: HDR disable command sent." >&2
    else
        echo "WARNING: Failed to send HDR disable command. HDR might still be on." >&2
    fi
    sleep 2 # Give a moment for the display mode to change
}

# Function to attempt to re-enable HDR
# Ideally, this would restore the exact previous state.
# For simplicity, we might just re-enable it if we know the command.
enable_hdr() {
    if [ -n "$HDR_ORIGINAL_STATE" ] || true; then # Or just always try to re-enable
        echo "INFO: Attempting to re-enable HDR on $KNOWN_PRIMARY_MONITOR_NAME..." >&2

        if kscreen-doctor output.$KNOWN_PRIMARY_MONITOR_NAME.hdr.enable; then
            echo "INFO: HDR re-enable command sent." >&2
        else
            echo "WARNING: Failed to send HDR re-enable command." >&2
        fi
    fi
}

trap enable_hdr EXIT SIGINT SIGTERM

# --- Script Setup ---
LOG_FILE="/tmp/polymc_splitscreen_launcher.log"
>"$LOG_FILE" # Clear log file at start
exec >>"$LOG_FILE" 2>&1 # Redirect script's stdout and stderr to log file
echo "--- Script started at $(date) ---"

# Function to get window ID by *multiple* Title Fragments.
# LOGS TO STDERR, ECHOS RESULT TO STDOUT
get_window_id_by_stable_title() {
    local search_label="$1"; local exclude_wid="$2"; shift 2; local title_fragments=("$@")
    local found_wid=""; local attempt_num=0
    echo "INFO ($search_label): Searching for window matching ALL fragments: [${title_fragments[*]}] , Exclude WID: '$exclude_wid'" >&2
    while [ -z "$found_wid" ] && [ "$attempt_num" -lt "$WINDOW_FIND_ATTEMPTS" ]; do
        echo "INFO ($search_label): Attempt $((attempt_num + 1))/$WINDOW_FIND_ATTEMPTS..." >&2
        local candidate_wid_cmd="wmctrl -l"; for frag in "${title_fragments[@]}"; do candidate_wid_cmd+=" | grep -iF \"$frag\""; done
        candidate_wid_cmd+=" | awk '{print \$1}'"
        if [ -n "$exclude_wid" ]; then if [[ "$exclude_wid" =~ ^0x[0-9a-fA-F]+$ ]]; then candidate_wid_cmd+=" | grep -v \"^${exclude_wid}$\""; else echo "DEBUG ($search_label): exclude_wid '$exclude_wid' invalid, not using." >&2; fi; fi
        candidate_wid_cmd+=" | head -n1"
        echo "DEBUG ($search_label): Executing: $candidate_wid_cmd" >&2
        candidate_wid=$(eval "$candidate_wid_cmd")
        if [ -n "$candidate_wid" ]; then if [[ "$candidate_wid" =~ ^0x[0-9a-fA-F]+$ ]]; then echo "INFO ($search_label): Found WID $candidate_wid." >&2; found_wid="$candidate_wid"; break; else echo "WARNING ($search_label): Candidate '$candidate_wid' not a WID." >&2; candidate_wid=""; fi; fi
        if [ -z "$found_wid" ]; then if [ $((attempt_num % 5)) -eq 0 ] || [ $attempt_num -eq 0 ]; then echo "DEBUG ($search_label): Not found. Windows:" >&2; wmctrl -l >&2 || echo "DEBUG: wmctrl -l failed" >&2; fi; sleep "$WINDOW_FIND_DELAY"; fi
        attempt_num=$((attempt_num + 1))
    done
    if [ -n "$found_wid" ]; then echo "$found_wid"; return 0; else echo "ERROR ($search_label): Could not find window." >&2; return 1; fi
}

# --- Main Logic ---
disable_hdr

PID1=""
PID2=""
WID1=""
WID2=""

echo "--- Script started at $(date) ---"

# --- Launch BOTH instances in quick succession first ---
echo "INFO: Launching PolyMC instance 1 (User1) in background..." >&2
eval "$FLATPAK_CMD run $POLYMC_ARGS_1 &"
PID1=$!
echo "INFO: PolyMC instance 1 (flatpak PID $PID1) launched." >&2

echo "INFO: Launching PolyMC instance 2 (User2) in background..." >&2
eval "$FLATPAK_CMD run $POLYMC_ARGS_2 &"
PID2=$!
echo "INFO: PolyMC instance 2 (flatpak PID $PID2) launched." >&2

# --- Wait for BOTH windows to appear and titles to stabilize ---
echo "INFO: Waiting ${LAUNCH_AND_TITLE_STABILIZE_WAIT}s for BOTH windows to appear and titles to stabilize..." >&2
sleep "$LAUNCH_AND_TITLE_STABILIZE_WAIT"

# --- Now find WID1 ---
echo "INFO: Attempting to find WID for Instance 1 using stable title fragments: '$STABLE_TITLE_FRAGMENT_1', '$STABLE_TITLE_FRAGMENT_2'..." >&2
WID1_OUTPUT=$(get_window_id_by_stable_title "Instance1_Search" "" "$STABLE_TITLE_FRAGMENT_1" "$STABLE_TITLE_FRAGMENT_2")
WID1_RET=$? 
WID1="$WID1_OUTPUT"

if [ $WID1_RET -ne 0 ] || [ -z "$WID1" ]; then
    cleanup_and_exit "Could not find window for Instance 1 with stable title (ret: $WID1_RET, WID: '$WID1')."
fi
echo "INFO: Found WID1: $WID1. Renaming its title to '$RENAMED_TITLE_1'." >&2
wmctrl -i -r "$WID1" -N "$RENAMED_TITLE_1"
if [ $? -ne 0 ]; then echo "WARNING: Failed to rename WID1. This might cause issues finding WID2." >&2; fi
sleep "$POST_RENAME_WAIT" 

# --- Then find WID2 (excluding WID1) ---
echo "INFO: Attempting to find WID for Instance 2 using stable title fragments: '$STABLE_TITLE_FRAGMENT_1', '$STABLE_TITLE_FRAGMENT_2', excluding WID1: $WID1 ..." >&2
WID2_OUTPUT=$(get_window_id_by_stable_title "Instance2_Search" "$WID1" "$STABLE_TITLE_FRAGMENT_1" "$STABLE_TITLE_FRAGMENT_2")
WID2_RET=$?
WID2="$WID2_OUTPUT"

if [ $WID2_RET -ne 0 ] || [ -z "$WID2" ]; then
    cleanup_and_exit "Could not find window for Instance 2 with stable title (ret: $WID2_RET, WID: '$WID2')."
fi
if [ "$WID1" == "$WID2" ]; then
    cleanup_and_exit "WID1 and WID2 are the same ($WID1), which is unexpected after renaming WID1."
fi

echo "INFO: Found WID2: $WID2. Renaming its title to '$RENAMED_TITLE_2'." >&2
wmctrl -i -r "$WID2" -N "$RENAMED_TITLE_2"
if [ $? -ne 0 ]; then echo "WARNING: Failed to rename WID2." >&2; fi
sleep "$POST_RENAME_WAIT"

echo "INFO: Successfully identified and renamed WID1: $WID1 ('$RENAMED_TITLE_1') and WID2: $WID2 ('$RENAMED_TITLE_2')" >&2

# --- Screen Dimension Parsing ---
PRIMARY_WIDTH=""; PRIMARY_HEIGHT=""; PRIMARY_OFFSET_X=""; PRIMARY_OFFSET_Y=""
MONITOR_INFO_SOURCE="Unknown"

echo "INFO: --- Starting Screen Dimension Parsing ---" >&2
XRANDR_OUTPUT=$(xrandr --query)
echo "DEBUG: Full xrandr --query output:" >&2
echo "$XRANDR_OUTPUT" >&2
echo "------------------------------------------" >&2

# Attempt 0: Look for a specific, known primary monitor by its name
if [ -n "$KNOWN_PRIMARY_MONITOR_NAME" ]; then
    echo "INFO: Attempt 0: Looking for known primary monitor by name: '$KNOWN_PRIMARY_MONITOR_NAME'" >&2
    # Grep for the line starting with the known name and also containing " connected " and geometry
    KNOWN_PRIMARY_LINE=$(echo "$XRANDR_OUTPUT" | grep "^${KNOWN_PRIMARY_MONITOR_NAME} connected [0-9]*x[0-9]*+[0-9]*+[0-9]*")

    if [ -n "$KNOWN_PRIMARY_LINE" ]; then
        echo "INFO: Found line matching known primary name '$KNOWN_PRIMARY_MONITOR_NAME' with geometry:" >&2
        echo "$KNOWN_PRIMARY_LINE" >&2
        # Regex to capture <width>x<height>+<xoffset>+<yoffset>
        if [[ "$KNOWN_PRIMARY_LINE" =~ ([0-9]+x[0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
            DIMENSIONS_STR="${BASH_REMATCH[1]}"
            PRIMARY_OFFSET_X="${BASH_REMATCH[2]}"
            PRIMARY_OFFSET_Y="${BASH_REMATCH[3]}"
            PRIMARY_WIDTH=$(echo "$DIMENSIONS_STR" | cut -dx -f1)
            PRIMARY_HEIGHT=$(echo "$DIMENSIONS_STR" | cut -dx -f2)
            MONITOR_INFO_SOURCE="xrandr (known name: $KNOWN_PRIMARY_MONITOR_NAME)"
            echo "INFO: Parsed from known primary line: W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
        else
            echo "WARNING: Found line for known primary name, but regex failed to parse geometry." >&2
            KNOWN_PRIMARY_LINE="" # Clear it so other methods are tried
        fi
    else
        echo "INFO: No line found matching known primary name '$KNOWN_PRIMARY_MONITOR_NAME' with connected geometry." >&2
    fi
fi
# You could add a similar block here for KNOWN_PRIMARY_MONITOR_GEOMETRY_SUBSTRING if you prefered that

# Attempt 1: Find line explicitly containing ' connected primary' (will likely fail for you but kept for robustness)
if [ -z "$PRIMARY_WIDTH" ]; then # Only if known primary wasn't found/parsed
    echo "INFO: Attempt 1: Looking for 'connected primary' keyword..." >&2
    PRIMARY_LINE=$(echo "$XRANDR_OUTPUT" | grep ' connected primary')
    if [ -n "$PRIMARY_LINE" ]; then
        echo "INFO: Found line with ' connected primary': $PRIMARY_LINE" >&2
        if [[ "$PRIMARY_LINE" =~ ([0-9]+x[0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
            DIMENSIONS_STR="${BASH_REMATCH[1]}"; PRIMARY_OFFSET_X="${BASH_REMATCH[2]}"; PRIMARY_OFFSET_Y="${BASH_REMATCH[3]}"
            PRIMARY_WIDTH=$(echo "$DIMENSIONS_STR" | cut -dx -f1); PRIMARY_HEIGHT=$(echo "$DIMENSIONS_STR" | cut -dx -f2)
            MONITOR_INFO_SOURCE="xrandr (explicit 'connected primary')"
            echo "INFO: Parsed: W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
        else
            echo "WARNING: 'connected primary' line found, but regex failed to parse geometry." >&2; PRIMARY_LINE=""
        fi
    else
        echo "INFO: No line found with ' connected primary'." >&2
    fi
fi

# Attempt 2: If still no specific primary, find the first 'connected' non-virtual monitor with geometry (heuristic)
if [ -z "$PRIMARY_WIDTH" ]; then
    echo "INFO: Attempt 2: Looking for first 'connected' active monitor (heuristic)..." >&2
    FIRST_CONNECTED_ACTIVE_LINE=$(echo "$XRANDR_OUTPUT" | grep ' connected [0-9]*x[0-9]*+[0-9]*+[0-9]*' | grep -v 'disconnected' | grep -Ev 'None-|VIRTUAL|Screen[0-9]' | head -n1)
    if [ -n "$FIRST_CONNECTED_ACTIVE_LINE" ]; then
        echo "INFO: Using first 'connected' line with geometry: $FIRST_CONNECTED_ACTIVE_LINE" >&2
        if [[ "$FIRST_CONNECTED_ACTIVE_LINE" =~ ([0-9]+x[0-9]+)\+([0-9]+)\+([0-9]+) ]]; then
            DIMENSIONS_STR="${BASH_REMATCH[1]}"; PRIMARY_OFFSET_X="${BASH_REMATCH[2]}"; PRIMARY_OFFSET_Y="${BASH_REMATCH[3]}"
            PRIMARY_WIDTH=$(echo "$DIMENSIONS_STR" | cut -dx -f1); PRIMARY_HEIGHT=$(echo "$DIMENSIONS_STR" | cut -dx -f2)
            MONITOR_INFO_SOURCE="xrandr (first connected with geometry heuristic)"
            echo "INFO: Parsed: W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
        else
            echo "WARNING: Found first 'connected' line with geometry, but regex failed: $FIRST_CONNECTED_ACTIVE_LINE" >&2
        fi
    else
        echo "INFO: No 'connected' line with parseable geometry found as a fallback heuristic." >&2
    fi
fi

# Attempt 3: Fallback to xdpyinfo (usually full desktop area)
if [ -z "$PRIMARY_WIDTH" ]; then
    echo "WARNING: Attempt 3: All xrandr parsing attempts failed. Falling back to xdpyinfo." >&2
    XDPY_DIMENSIONS=$(xdpyinfo | grep dimensions | sed -r 's/^[^0-9]*([0-9]+x[0-9]+).*$/\1/')
    if [ -n "$XDPY_DIMENSIONS" ]; then
        PRIMARY_WIDTH=$(echo "$XDPY_DIMENSIONS" | cut -dx -f1); PRIMARY_HEIGHT=$(echo "$XDPY_DIMENSIONS" | cut -dx -f2)
        PRIMARY_OFFSET_X=0; PRIMARY_OFFSET_Y=0
        MONITOR_INFO_SOURCE="xdpyinfo (full desktop fallback)"
        echo "INFO: Using xdpyinfo: W=$PRIMARY_WIDTH, H=$PRIMARY_HEIGHT, X=$PRIMARY_OFFSET_X, Y=$PRIMARY_OFFSET_Y" >&2
    fi
fi

# Final check for valid dimensions
if ! [[ "$PRIMARY_WIDTH" =~ ^[0-9]+$ && "$PRIMARY_HEIGHT" =~ ^[0-9]+$ && "$PRIMARY_OFFSET_X" =~ ^[0-9]+$ && "$PRIMARY_OFFSET_Y" =~ ^[0-9]+$ ]]; then
    cleanup_and_exit "Could not reliably determine screen dimensions/offsets. Final Source: $MONITOR_INFO_SOURCE. Parsed: W='$PRIMARY_WIDTH', H='$PRIMARY_HEIGHT', X='$PRIMARY_OFFSET_X', Y='$PRIMARY_OFFSET_Y'"
fi
echo "INFO: FINAL Using screen area for split ($MONITOR_INFO_SOURCE): W=${PRIMARY_WIDTH}, H=${PRIMARY_HEIGHT} at offset X=${PRIMARY_OFFSET_X}, Y=${PRIMARY_OFFSET_Y}" >&2

# Target sizes and positions (rest of the script assumes these are now correct for the intended monitor)
TARGET_W1=$((PRIMARY_WIDTH / 2))
TARGET_W2=$((PRIMARY_WIDTH - TARGET_W1))
POS_X1=$PRIMARY_OFFSET_X
POS_Y1=$PRIMARY_OFFSET_Y
SIZE_W1=$TARGET_W1
SIZE_H1=$PRIMARY_HEIGHT

POS_X2=$((PRIMARY_OFFSET_X + TARGET_W1))
POS_Y2=$PRIMARY_OFFSET_Y
SIZE_W2=$TARGET_W2
SIZE_H2=$PRIMARY_HEIGHT


# --- Launch and Manage Instances ---
launch_and_get_wid() {
    local instance_num=$1; local pid_var_name=$2; local polymc_args=$3; local search_label=$4; local exclude_wid_for_search=$5
    local found_output; local found_ret; local actual_wid
    echo "INFO: Launching PolyMC instance $instance_num..." >&2
    eval "$FLATPAK_CMD run $polymc_args &"
    eval "$pid_var_name=$!" # Store PID in the variable name passed
    echo "INFO: PolyMC instance $instance_num (flatpak PID ${!pid_var_name}) launched. Waiting ${LAUNCH_AND_TITLE_STABILIZE_WAIT}s..." >&2
    sleep "$LAUNCH_AND_TITLE_STABILIZE_WAIT"
    echo "INFO: Attempting to find WID for Instance $instance_num..." >&2
    found_output=$(get_window_id_by_window_title "$search_label" "$exclude_wid_for_search" "$PART_OF_WINDOW_TITLE")
    found_ret=$?
    actual_wid="$found_output"
    if [ $found_ret -ne 0 ] || [ -z "$actual_wid" ]; then cleanup_and_exit "Could not find WID for Instance $instance_num."; fi
    echo "$actual_wid" # Return WID
}

WID1=$(launch_and_get_wid 1 PID1 "$POLYMC_ARGS_1" "Instance1_Search" "")
echo "INFO: Found WID1: $WID1. Renaming to '$RENAMED_TITLE_1'." >&2
wmctrl -i -r "$WID1" -N "$RENAMED_TITLE_1"; sleep "$POST_RENAME_WAIT"

WID2=$(launch_and_get_wid 2 PID2 "$POLYMC_ARGS_2" "Instance2_Search" "$WID1")
if [ "$WID1" == "$WID2" ]; then cleanup_and_exit "WID1 and WID2 are the same ($WID1)."; fi
echo "INFO: Found WID2: $WID2. Renaming to '$RENAMED_TITLE_2'." >&2
wmctrl -i -r "$WID2" -N "$RENAMED_TITLE_2"; sleep "$POST_RENAME_WAIT"

echo "INFO: Successfully identified WID1: $WID1 and WID2: $WID2" >&2

# --- Window Management Function (Optimized for Speed) ---
manage_window() {
    local WID="$1"; local TARGET_X="$2"; local TARGET_Y="$3"; local TARGET_W="$4"; local TARGET_H="$5"; local W_NAME="$6"
    echo "INFO ($W_NAME): Managing window $WID. Target: X=$TARGET_X, Y=$TARGET_Y, W=$TARGET_W, H=$TARGET_H" >&2
    if [ -z "$WID" ]; then echo "ERROR ($W_NAME): Window ID is empty." >&2; return 1; fi

    echo "INFO ($W_NAME): Initial attempt to activate and normalize $WID." >&2
    wmctrl -i -a "$WID"; sleep 0.2 # Quick activation
    wmctrl -i -r "$WID" -b remove,fullscreen; sleep "$WINDOW_MANIP_DELAY_SHORT"
    wmctrl -i -r "$WID" -b remove,maximized_vert,maximized_horz; sleep "$WINDOW_MANIP_DELAY_SHORT"

    echo "INFO ($W_NAME): Attempting to move/resize $WID." >&2
    wmctrl -i -r "$WID" -e "0,${TARGET_X},${TARGET_Y},${TARGET_W},${TARGET_H}"
    local ret_resize=$?

    if [ $ret_resize -ne 0 ]; then
        echo "WARNING ($W_NAME): Initial resize/move failed (code $ret_resize). Retrying with more normalization..." >&2
        wmctrl -i -a "$WID"; sleep 0.2
        wmctrl -i -r "$WID" -b remove,fullscreen; sleep "$WINDOW_MANIP_DELAY_NORMAL"
        wmctrl -i -r "$WID" -b remove,maximized_vert,maximized_horz; sleep "$WINDOW_MANIP_DELAY_NORMAL"
        echo "INFO ($W_NAME): Retrying move/resize $WID." >&2
        wmctrl -i -r "$WID" -e "0,${TARGET_X},${TARGET_Y},${TARGET_W},${TARGET_H}"
        if [ $? -ne 0 ]; then echo "ERROR ($W_NAME): Retry of resize/move also failed." >&2; else echo "INFO ($W_NAME): Retry resize/move successful." >&2; fi
    else
        echo "INFO ($W_NAME): Initial resize/move successful." >&2
    fi
    sleep "$WINDOW_MANIP_DELAY_SHORT" # Final settle
}

echo "INFO: Managing WID1 ($WID1) - placing on RIGHT" >&2
manage_window "$WID1" "$POS_X2" "$POS_Y2" "$SIZE_W2" "$SIZE_H2" "WID1" # WID1 now gets POS_X2/SIZE_W2 (right side)

echo "INFO: Managing WID2 ($WID2) - placing on LEFT" >&2
manage_window "$WID2" "$POS_X1" "$POS_Y1" "$SIZE_W1" "$SIZE_H1" "WID2" # WID2 now gets POS_X1/SIZE_W1 (left side)

echo "INFO: Activating WID1 for input focus." >&2
wmctrl -i -a "$WID1"

echo "INFO: Window positioning complete. Script will now monitor game windows WID1 ($WID1) and WID2 ($WID2) and exit when both are closed." >&2

# Function to check if a window ID still exists
window_exists() {
    local wid_to_check="$1"
    if [ -z "$wid_to_check" ]; then return 1; fi # No WID passed
    wmctrl -l | grep -q "^${wid_to_check} " # -q for quiet, returns 0 if found, 1 if not
    return $?
}

# Loop and wait until both windows are gone
# Or if one of the WIDs was never valid (though earlier checks should prevent this)
while ( [ -n "$WID1" ] && window_exists "$WID1" ) || ( [ -n "$WID2" ] && window_exists "$WID2" ); do
    # Check more frequently at first, then less often to reduce CPU usage
    # This is a simple example; more sophisticated backoff could be used.
    if [[ $(ps -o etimes= -p $$) -lt 60 ]]; then # If script running less than 60s
        sleep 2 # Check every 2 seconds
    else
        sleep 5 # Check every 5 seconds
    fi

    # Optional: Log which window is still alive for debugging long waits
    # if [ -n "$WID1" ] && window_exists "$WID1" ]; then echo "DEBUG: WID1 ($WID1) still alive." >&2; fi
    # if [ -n "$WID2" ] && window_exists "$WID2" ]; then echo "DEBUG: WID2 ($WID2) still alive." >&2; fi
done

echo "INFO: Both game windows WID1 ($WID1) and WID2 ($WID2) appear to have closed." >&2

# Optional: Attempt to clean up the original flatpak PIDs if they are still somehow running (unlikely but possible)
if [ -n "$PID1" ] && ps -p "$PID1" > /dev/null; then
    echo "INFO: Attempting to ensure original flatpak process PID1 ($PID1) is terminated." >&2
    kill "$PID1" 2>/dev/null
    sleep 0.5
    kill -9 "$PID1" 2>/dev/null # Force kill if still there
fi
if [ -n "$PID2" ] && ps -p "$PID2" > /dev/null; then
    echo "INFO: Attempting to ensure original flatpak process PID2 ($PID2) is terminated." >&2
    kill "$PID2" 2>/dev/null
    sleep 0.5
    kill -9 "$PID2" 2>/dev/null
fi

echo "INFO: Script finished." >&2
exit 0
