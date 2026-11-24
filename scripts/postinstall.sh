#!/usr/bin/env bash
# Package postinstall: runs as root after the files are installed.
# Restarts the user's running daemon (and app) so the new version takes effect.
# Nothing here may fail the installation.

AGENT_LABEL="com.house-keeping.agent"
APP_BUNDLE_ID="com.house-keeping.app"

# The installer runs as root; find the user who is logged in at the console.
REAL_USER="$(stat -f %Su /dev/console 2>/dev/null)"
if [[ -z "$REAL_USER" || "$REAL_USER" == "root" || "$REAL_USER" == "loginwindow" ]]; then
    REAL_USER="${SUDO_USER:-}"
fi
REAL_UID=""
if [[ -n "$REAL_USER" && "$REAL_USER" != "root" ]]; then
    REAL_UID="$(id -u "$REAL_USER" 2>/dev/null)"
fi

run_as_user() {
    if [[ "$(id -u)" == "$REAL_UID" ]]; then
        "$@"
    else
        launchctl asuser "$REAL_UID" sudo -u "$REAL_USER" "$@"
    fi
}

if [[ -n "$REAL_UID" ]]; then
    REAL_HOME="$(dscl . -read "/Users/$REAL_USER" NFSHomeDirectory 2>/dev/null | awk '{print $2}')"
    if [[ -n "$REAL_HOME" ]]; then
        mkdir -p "$REAL_HOME/Library/Logs/house_keeping"
        chown "$REAL_USER" "$REAL_HOME/Library/Logs/house_keeping"
    fi

    # Quit the app first (it keeps running the old code otherwise), and reopen it afterwards.
    APP_WAS_RUNNING=0
    if run_as_user osascript -e "application id \"$APP_BUNDLE_ID\" is running" 2>/dev/null | grep -q true; then
        APP_WAS_RUNNING=1
        run_as_user osascript -e "tell application id \"$APP_BUNDLE_ID\" to quit" >/dev/null 2>&1
        for _ in 1 2 3 4 5 6 7 8 9 10; do
            run_as_user osascript -e "application id \"$APP_BUNDLE_ID\" is running" 2>/dev/null | grep -q true || break
            sleep 0.5
        done
    fi

    # Restart the daemon only if the user has it installed as a launch agent.
    if launchctl print "gui/$REAL_UID/$AGENT_LABEL" >/dev/null 2>&1; then
        if launchctl kickstart -k "gui/$REAL_UID/$AGENT_LABEL" >/dev/null 2>&1; then
            echo "Restarted the house_keeping daemon."
        else
            echo "Could not restart the daemon. Run: launchctl kickstart -k gui/\$(id -u)/$AGENT_LABEL"
        fi
    fi

    if [[ "$APP_WAS_RUNNING" == "1" ]]; then
        run_as_user open -b "$APP_BUNDLE_ID" >/dev/null 2>&1
    fi
fi

echo ""
echo "house_keeping installed to /usr/local/bin/house_keeping"
echo "Open House Keeping in Applications to edit rules and enable Start at login."
echo ""
echo "Quick start:"
echo "  1. Create ~/.config/house_keeping/config.yaml using the README Quick Start."
echo "  2. Validate:        house_keeping check --verbose"
echo "  3. Preview:         house_keeping dry-run"
echo "  4. Auto-start:      house_keeping install"
echo ""
exit 0
