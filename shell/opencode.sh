#!/usr/bin/env bash

REAL_OPENCODE="/root/.opencode/bin/opencode"

# 1. Check if the arguments contain any info-only flags that should skip screen restoration
SKIP_RESTORE=0
for arg in "$@"; do
    if [ "$arg" = "-h" ] || [ "$arg" = "--help" ] || [ "$arg" = "-v" ] || [ "$arg" = "--version" ]; then
        SKIP_RESTORE=1
        break
    fi
done

# 2. Execute the actual opencode binary and pass all arguments through
"$REAL_OPENCODE" "$@"

# 3. If a help or version flag was used, exit immediately to keep the output on screen
if [ "$SKIP_RESTORE" -eq 1 ]; then
    exit 0
fi

# 4. Upon normal interactive exit:
# \033[?1049l : Exit the alternate screen buffer to restore pre-execution state
# \033[?1003l : Disable all mouse movement/click tracking to prevent coordinate garbage text
# \033[?1000l : Disable basic mouse click tracking
# \033[?1004l : Disable window focus tracking (prevents both '^[[I' and '^[[O' stray events)
# \033[0m     : Reset text styling and colors
# printf "\033[?1049l\033[?1003l\033[?1000l\033[?1004l\033[0m"

# 4. Upon normal interactive exit, perform a hard reset to prevent ANY garbage text
reset > /dev/null 2>&1
