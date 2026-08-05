#!/usr/bin/env bash
#
# The feature set for this fork's build.
#
# These are plain UserDefaults keys, so this deliberately is not a code change:
# editing the `default:` values in Constants.swift would give the same result
# while conflicting with upstream on every release. Run it once after installing;
# re-run it any time to reset the configuration.
#
#   ./scripts/apply-my-defaults.sh

set -euo pipefail

DOMAIN="${DOMAIN:-com.vlnd0.Atoll}"   # use com.vlnd0.Atoll.dev for a Debug build

on()  { defaults write "$DOMAIN" "$1" -bool true; }
off() { defaults write "$DOMAIN" "$1" -bool false; }
str() { defaults write "$DOMAIN" "$1" -string "$2"; }

# Matched by path, not by process name: the fork's executable is also called
# "Atoll", so `pkill -x Atoll` would take a stock Atoll down with it.
pkill -f "/Applications/Atoll Fork.app" 2>/dev/null || true

# ── Layout ───────────────────────────────────────────────────────────────────
str tabBarPosition left          # rail down the leading edge, not a header row
on  tabSwitchOnHover             # resting the pointer on a tab selects it

# ── Ported from Cyclop ───────────────────────────────────────────────────────
on  enableSnippetsFeature        # pinned texts, ~/Library/Application Support/Atoll/snippets.json
on  enableTranslateFeature       # offline EN <-> RU, needs macOS 15

# ── Tabs kept ────────────────────────────────────────────────────────────────
on  showStandardMediaControls    # Home
on  showCalendar
on  dynamicShelf                 # Shelf
on  enableLLMUsageFeature        # Usage — token counter
on  enableClaudeProvider
on  enableCodexProvider
off enableCursorProvider
off enableAntigravityProvider

# ── Tabs dropped ─────────────────────────────────────────────────────────────
off enableStatsFeature
off enableTerminalFeature
off enableNotes
str timerDisplayMode popover     # timer stays, but not as a tab

# ── Clipboard: kept, as a header popup (the screenshot vault needs it) ────────
on  enableClipboardManager
str clipboardDisplayMode popover
on  showClipboardIcon

# ── System interception: off ─────────────────────────────────────────────────
off enableSystemHUD
off enableVolumeHUD
off enableBrightnessHUD
off enableKeyboardBacklightHUD
off enableCustomOSD
off enableCameraDetection        # with PR #692 this now actually stops the monitor
off enableMicrophoneDetection
off enableScreenRecordingDetection
off enableDoNotDisturbDetection
off enableCapsLockIndicator
off showBluetoothDeviceConnections
off showAirPodsListeningModeChanges
off showPowerStatusNotifications
off showChargingBatteryHUD
off showLowBatteryHUD
off showFullBatteryHUD

# ── Lock screen widgets: kept ────────────────────────────────────────────────
on  enableLockScreenLiveActivity
on  enableLockScreenMediaWidget
off enableLockScreenWeatherWidget   # 42 KB of manager and network requests
off enableLockScreenFocusWidget
off enableLockScreenReminderWidget
off enableLockScreenTimerWidget

# ── Extras: off ──────────────────────────────────────────────────────────────
off enableColorPickerFeature
off enableScreenAssistant
off enableThirdPartyExtensions
off enableBetterDisplayIntegration
off enableLunarIntegration
off enableThirdPartyDDCIntegration
off enableRealTimeWaveform
off showMirror
off showNotHumanFace
off enableLyrics

echo "Applied to $DOMAIN. Start Atoll Fork to pick it up."
