#!/bin/bash

# Jamf policy script parameters, e.g. below:
# [ "$4" != "" ] && [ "$targetosverion" == "" ] && [ "$targetosverion" == "$4" ]
# [ "$5" != "" ] && [ "$targetosverion" == "" ] && [ "$targetosverion" == "$5" ]
# targetosverion="$4"
# macosname="$5"

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

plist_path=/usr/local/."defer_update.plist"
if [[ ! -f "$plist_path" ]]; then
  /usr/libexec/PlistBuddy -c "Add :deferred integer 3" "$plist_path"
fi

user=$(id -P $(stat -f%Su /dev/console) | cut -d : -f 8 | cut -d " " -f1)
serial=$(system_profiler SPHardwareDataType | awk '/Serial/ {print $4}')
model=$(sysctl hw.model | awk '/hw.model:/ {print $2}')
osversion=$(sw_vers -productVersion)
platform_arch=$(/usr/bin/arch)
jamfHelper="/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper"
plist_var="$(/usr/libexec/PlistBuddy -c 'print ":deferred"' $plist_path)"
power_source=$(pmset -g batt | head -n 1 | cut -d \' -f2)
CURRENT_USER=$(/usr/bin/stat -f%Su "/dev/console")
USER_ID=$(/usr/bin/id -u "$CURRENT_USER")

# set the variables as needed
###################################################################################################
customicon="/usr/local/.ventura_icon.png"
macosname="Ventura"
targetosverion="13.0.0"
description=$(echo"$message")
heading="Update Now  macOS "$macosname" "$targetosverion""
defer_button="Defer Update"
update_button="Update Now"
message="
Hello "$user",
                                                          
Your computer requires a mandatory update to macOS "$macosname" "$targetosverion"
                                                          
Model: "$model"
Serial: "$serial"
Computer Platform: "$platform_arch"
Current macOS: "$osversion"
                                                          
- IT ❤️
                                                          
-----------------------------------------------------------------------------
                                                          
Note: This process takes up to 30 minutes or more to complete
                                                          
⚠️ Please save any unsaved work - "$plist_var" deferrals remaining ⚠️"
##############################################################################################

echo "Power Source: $power_source"
echo "Platform: $platform_arch"
echo "Running: macOS $osversion"
echo "Targeting: macOS $targetosverion"

if [[ ! -f $customicon ]]; then
  echo "customicon not found"
  customicon="/System/Library/PreferencePanes/SoftwareUpdate.prefPane/Contents/Resources/SoftwareUpdate.icns"
fi

if [[ ${osversion} = "$targetosverion" ]] || [[ ${osversion} > "$targetosverion" ]]; then
  rm -f "$plist_path"
fi

check_jamfhelper() {
  if [[ ! -f "/Library/Application Support/JAMF/bin/jamfHelper.app/Contents/MacOS/jamfHelper" ]]; then
    echo "jamfHelper not found, exiting..."
    exit 1
  fi
}

defer_check() {
  if [[ "$plist_var" = 0 ]]; then
    if [[ ${osversion} != "$targetosverion" ]] && [[ ${osversion} < "$targetosverion" ]] && [[ -z $(ps axco pid,command | grep "com.apple.preferences.softwareupdate.remoteservice") ]]; then
      sudo ps axco pid,command | grep jamfHelper | awk '{ print $1; }' | xargs sudo kill -9
      echo "${osversion} != "$targetosverion" - showing dialog - 0 deferral"
      if [[ "$platform_arch" = "i386" ]]; then
        check=$("$jamfHelper" -windowType utility -lockHUD -title "$title" -description "$message" -alignDescription center \
          -button1 "$update_button" -icon "$customicon" -iconSize 128 -heading "$heading" -alignHeading center -timeout 600 -countdown -alignCountdown right -defaultButton 1)
      else
        check=$("$jamfHelper" -windowType utility -lockHUD -title "$heading" -description "$message" \
          -button1 "$update_button" -icon "$customicon" -iconSize 128 -timeout 600 -countdown -alignCountdown right -defaultButton 1)
      fi
      if [[ ${check} -eq 0 ]] && [[ ${check} != "" ]]; then
        echo "Update: No deferral left, showing dialog"
        run_updates
      fi
    else
      echo "Skipping - osversion "$osversion" >= targetosverion "$targetosverion" or systempref software update already open"
      exit 0
    fi
  else
    defer_jamfhelper
  fi
}

defer_jamfhelper() {
  if [[ "$power_source" != "Battery Power" ]]; then
    if [[ ${osversion} != "" ]] && [[ "${targetosverion}" != "" ]]; then
      if [[ -f "$plist_path" ]]; then
        if [[ ${osversion} != "$targetosverion" ]] && [[ ${osversion} < "$targetosverion" ]] && [[ -z $(ps axco pid,command | grep "com.apple.preferences.softwareupdate.remoteservice") ]]; then
          echo "${osversion} != ${targetosverion} - showing dialog"
          sudo ps axco pid,command | grep jamfHelper | awk '{ print $1; }' | xargs sudo kill -9
          if [[ "$platform_arch" = "i386" ]]; then
            check=$("$jamfHelper" -windowType utility -description "$message" -alignDescription center \
              -button1 "$update_button" -button2 "$defer_button" -icon "$customicon" -iconSize 128 -heading "$heading" -alignHeading center -defaultButton 1)
          else
            check=$("$jamfHelper" -windowType utility -lockHUD -title "$heading" -description "$message" \
              -button1 "$update_button" -button2 "$defer_button" -icon "$customicon" -iconSize 128 -defaultButton 1)
          fi
          if [[ ${check} -eq 0 ]] && [[ ${check} != "" ]]; then
            echo "Opening System Prefs..."
            run_updates
          elif [[ ${check} -eq 2 ]] && [[ ${check} != "" ]]; then
            echo "Update: deferred"
            defer_plist
          else
            echo "Update: cancelled"
          fi
        else
          echo "Skipping - osversion "$osversion" >= targetosverion "$targetosverion" or systempref software update already open"
          exit 0
        fi
      else
        if [[ ${osversion} != "$targetosverion" ]] && [[ ${osversion} < "$targetosverion" ]] && [[ -z $(ps axco pid,command | grep "com.apple.preferences.softwareupdate.remoteservice") ]]; then
          run_updates
        else
          echo "Skipping - osversion "$osversion" >= targetosverion "$targetosverion" or systempref software update already open"
          exit 0
        fi
      fi
    fi
  fi
}

defer_plist() {
  defer_count=$(/usr/libexec/PlistBuddy -c 'print ":deferred"' "$plist_path")
  if [[ "$defer_count" -gt 2 ]]; then
    /usr/libexec/PlistBuddy -c "set :deferred 2" $plist_path
  elif [[ "$defer_count" == 2 ]]; then
    /usr/libexec/PlistBuddy -c "set :deferred 1" $plist_path
  elif [[ "$defer_count" == 1 ]]; then
    /usr/libexec/PlistBuddy -c "set :deferred 0" $plist_path
  fi
  echo "Plist: defers remaining $(/usr/libexec/PlistBuddy -c 'print ":deferred"' $plist_path)"
}

run_updates() {
  if /usr/bin/fdesetup status | /usr/bin/grep -q "in progress"; then
    echo "❌ ERROR: FileVault encryption or decryption is in progress."
    exit 1
  fi

  if nc -zw1 swscan.apple.com 443; then
    echo "Connected to Apple servers, continuing"
  else
    echo "❌ ERROR: No connection to the Internet."
    exit 1
  fi

  heading="Update Now  macOS "$macosname" "$targetosverion""
  message="- Select Update/Upgrade
- Then select Restart

Note: Stay connected to power source"
  echo "Prompting System Preferences > Software Update..."
  open "/System/Library/PreferencePanes/SoftwareUpdate.prefPane"
  dialog=$("$jamfHelper" -windowType utility -windowPosition "ur" -icon "$customicon" -title "$heading" -description "$message" -timeout 15)
  exit 0
}

main() {
  if nc -zw1 swscan.apple.com 443; then
    if [[ "$power_source" != "Battery Power" ]]; then
      check_jamfhelper
      defer_check
    else
      echo 'Power Source: Battery Power - Must be connected to Power Source to run updates'
      exit 1
    fi
  else
    echo "❌ ERROR: No connection to the Internet."
  fi
}

main
