#!/bin/zsh
# Website screenshots of the popover and Settings, in English and Slovak (apps/site/images).
#
# Usage: apps/macos/scripts/site-screenshots.sh [en|sk ...]
#
# - Build the Debug app first (apps/macos/README.md). It runs with -screenshotMode YES:
#   no Screen Recording permission is necessary, the Screen switch is off (Audio only).
# - The popover uses invented sample sessions from site_samples.py in a temporary folder.
# - The Minutes icon must be visible in the menu bar. A menu bar manager must not hide it.
# - Terminal needs Accessibility (System Events) and Screen Recording (screencapture).
# - Look at every image before you commit it: no real meetings, names or internal addresses.
set -u
here=${0:A:h}
repo=${here:h:h:h}
app=$repo/apps/macos/build/DerivedData/Build/Products/Debug/Minutes.app
images=$repo/apps/site/images
work=$(mktemp -d)
trap 'rm -rf $work' EXIT
[[ -d $app ]] || { echo "Build the Debug app first: $app"; exit 1; }

# Window list helper: window number, layer and bounds of the Minutes windows.
cat > $work/win.swift <<'SWIFT'
import CoreGraphics
let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "Minutes" {
    print(w["kCGWindowNumber"]!, w["kCGWindowLayer"]!)
}
SWIFT
swiftc -O $work/win.swift -o $work/win || exit 1

ax() { osascript -e "tell application \"System Events\" to tell process \"Minutes\" to $1" >/dev/null 2>&1; }
activate() { osascript -e 'tell application id "sk.softverse.OfflineMeetingSummary" to activate' >/dev/null 2>&1; }
quit_app() {
  osascript -e 'quit app "Minutes"' >/dev/null 2>&1
  for i in {1..30}; do pgrep -x Minutes >/dev/null || break; sleep 0.5; done
  sleep 1.5
}
launch() { # <lang> <sessions folder>
  quit_app
  for t in 1 2 3; do
    open $app --args -screenshotMode YES -captureScreen NO -sessionsFolder $2 -AppleLanguages "($1)" -appLanguage $1
    sleep 4; pgrep -x Minutes >/dev/null && break
  done
}
# <file> <window layer: 101 popover, 0 window> [expected width]
grab() {
  local id w
  for t in 1 2 3 4; do
    activate; sleep 1.5
    id=$($work/win | awk -v l=$2 '$2==l{print $1; exit}')
    [[ -n $id ]] && screencapture -x -l$id $1
    w=$(sips -g pixelWidth $1 2>/dev/null | awk '/pixelWidth/{print $2}')
    [[ -n $w && ( -z ${3:-} || $w == ${3:-} ) ]] && { echo "  ${1:t} ($w px)"; return 0; }
  done
  echo "  FAILED ${1:t}"; return 1
}

shoot() { # <lang>
  local lang=$1 suffix=""; [[ $lang == sk ]] && suffix="-sk"
  echo "$lang"
  python3 -I $here/site_samples.py $work/samples-$lang $lang >/dev/null
  launch $lang $work/samples-$lang
  for i in {1..60}; do ax 'get menu bar 2' && break; sleep 1; done
  ax 'get menu bar 2' || { echo "The Minutes icon is not in the menu bar."; return 1; }
  sleep 2
  for t in 1 2 3 4 5; do ax 'click menu bar item 1 of menu bar 2'; sleep 2; ax 'get window 1' && break; done
  ax 'click radio button 1 of radio group 1 of group 1 of window 1'
  grab $images/popover-new-session$suffix.png 101
  ax 'click radio button 2 of radio group 1 of group 1 of window 1'
  grab $images/popover-sessions$suffix.png 101
  # The third session is "sprint planning" with two summaries. Open it and the summary form.
  ax 'perform action "AXPress" of button 3 of UI element 1 of scroll area 1 of group 1 of window 1'; sleep 1.5
  ax 'perform action "AXPress" of (last button of scroll area 1 of group 1 of window 1)'
  grab $images/popover-session$suffix.png 101

  # Settings with the default sessions folder, so the path shows as ~/Meetings.
  launch $lang $HOME/Meetings
  for t in 1 2 3 4 5 6; do
    activate; sleep 1
    osascript -e 'tell application "System Events" to tell process "Minutes" to keystroke "," using command down'
    sleep 2; ax 'get (first window whose subrole is "AXStandardWindow")' && break
  done
  local names=(general recording transcription summary models about)
  for i in {1..6}; do
    ax "click button $i of toolbar 1 of (first window whose subrole is \"AXStandardWindow\")"
    ax 'perform action "AXRaise" of (first window whose subrole is "AXStandardWindow")'
    # 1504 px is the window with its shadow. Without the shadow, the window was not active.
    grab $images/settings-$names[$i]$suffix.png 0 1504
  done
}

language=$(defaults read sk.softverse.OfflineMeetingSummary AppleLanguages 2>/dev/null | tr -d ' \n()"')
for lang in ${@:-en sk}; do shoot $lang; done
quit_app
# -appLanguage writes AppleLanguages for the app. Put the earlier value back.
if [[ -n $language ]]; then defaults write sk.softverse.OfflineMeetingSummary AppleLanguages -array $language
else defaults delete sk.softverse.OfflineMeetingSummary AppleLanguages 2>/dev/null; fi
echo "Done. Check the images in $images before you commit them."
