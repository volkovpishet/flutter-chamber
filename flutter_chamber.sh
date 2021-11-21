#!/usr/bin/env bash
# Intended to be used with macOS gitlab runner or locally.
# Makes builds more stable and easier to reproduce in macOS environment. See code to see what can be configured
# Warning! Intended to be run from flutter project root with FVM support
# This is not fully sandbox environment. Side effects still here, and external deps too.
# Nix is required to prepare the env and base binaries, Xcode is needed for iOS builds.
# Inspired by chamber script https://gist.github.com/fkorotkov/a483192df78f7a636b4aa0d036f7e228/
# Usage: ./flutter_chamber.sh "YOUR SHELL COMMAND AS STRING"

set -e # fall quickly in case of any errors

# Pass ENV variables to customize
# HOME_NAME - any unique name
# BUNDLER_VERSION - version you need

TARGET_COMMAND=$1;
WORKING_DIRECTORY="$PWD"
ORIGINAL_HOME=$HOME;
SANDBOX_HOME=$TMPDIR/$HOME_NAME
SANDBOX_OS_SPECIFIC_BINARIES_PATH="$SANDBOX_HOME/bin";

XCODE_DERIVED_DATA_DIR="$ORIGINAL_HOME/Library/Developer/Xcode/DerivedData"
XCODE_SIMULATOR_DEVICES_DIR="$ORIGINAL_HOME/Library/Developer/Xcode/UserData/IB Support/Simulator Devices"
XCODE_SIMULATOR_LOGS_DIR="$ORIGINAL_HOME/Library/Logs/CoreSimulator"
ORIGINAL_HOME_FLUTTER_CONFIG_DIR="$ORIGINAL_HOME/.config/flutter"
ORIGINAL_HOME_FVM_DIR="$ORIGINAL_HOME/fvm"
KEYCHAIN_PATH_RELATIVE_TO_HOME="Library/Keychains";
ORIGINAL_KEYCHAIN_DIR="$ORIGINAL_HOME/$KEYCHAIN_PATH_RELATIVE_TO_HOME";
SANDBOX_HOME_KEYCHAIN_DIR="$SANDBOX_HOME/$KEYCHAIN_PATH_RELATIVE_TO_HOME";
SECURITY_PREFERENCES_FILE_RELATIVE_TO_HOME="Library/Preferences/com.apple.security.plist";
ORIGINAL_SECURITY_PREFERENCES_FILE="$ORIGINAL_HOME/$SECURITY_PREFERENCES_FILE_RELATIVE_TO_HOME";
SANDBOX_HOME_PREFERENCES_FILE="$SANDBOX_HOME/$SECURITY_PREFERENCES_FILE_RELATIVE_TO_HOME";
PROVISIONING_PROFILES_PATH_RELATIVE_TO_HOME="Library/MobileDevice/Provisioning Profiles";
ORIGINAL_PROVISIONING_PROFILES_DIR="$ORIGINAL_HOME/$PROVISIONING_PROFILES_PATH_RELATIVE_TO_HOME";
SANDBOX_PROVISIONING_PROFILES_DIR="$SANDBOX_HOME/$PROVISIONING_PROFILES_PATH_RELATIVE_TO_HOME";

mkdir -p "$SANDBOX_HOME"
echo "$SANDBOX_HOME will be used as sandbox home dir"

# Original home will be partially writable. Create folders in original home, in case they do not exist
mkdir -p "$XCODE_DERIVED_DATA_DIR";
mkdir -p "$XCODE_SIMULATOR_DEVICES_DIR";
mkdir -p "$XCODE_SIMULATOR_LOGS_DIR";
mkdir -p "$ORIGINAL_HOME_FLUTTER_CONFIG_DIR";
mkdir -p "$ORIGINAL_HOME_FVM_DIR";

# Symlink keychains related data to original home directory
mkdir -p "$(dirname "$SANDBOX_HOME_KEYCHAIN_DIR")"
ln -s -f "$ORIGINAL_KEYCHAIN_DIR" "$(dirname "$SANDBOX_HOME_KEYCHAIN_DIR")";
mkdir -p "$(dirname "$SANDBOX_HOME_PREFERENCES_FILE")"
ln -s -f "$ORIGINAL_SECURITY_PREFERENCES_FILE" "$SANDBOX_HOME_PREFERENCES_FILE";

# Symlink provisioning profiles dir
mkdir -p "$(dirname "$SANDBOX_PROVISIONING_PROFILES_DIR")"
mkdir -p "$ORIGINAL_PROVISIONING_PROFILES_DIR";
ln -s -f "$ORIGINAL_PROVISIONING_PROFILES_DIR" "$(dirname "$SANDBOX_PROVISIONING_PROFILES_DIR")";

# Symlink binaries which could not be provided by nix environment
mkdir -p "$SANDBOX_OS_SPECIFIC_BINARIES_PATH";
ln -s -f /usr/bin/sandbox-exec "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/sandbox-exec;
ln -s -f /usr/bin/sw_vers "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/sw_vers;
ln -s -f /usr/bin/xcrun "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/xcrun;
ln -s -f /usr/bin/xcode-select "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/xcode-select;
ln -s -f /usr/bin/xcodebuild "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/xcodebuild;
ln -s -f /usr/bin/security "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/security;
ln -s -f /usr/bin/codesign "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/codesign;
ln -s -f /usr/bin/productbuild "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/productbuild;
ln -s -f /usr/bin/dwarfdump "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/dwarfdump;
ln -s -f /usr/bin/xattr "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/xattr;
ln -s -f /usr/sbin/sysctl "$SANDBOX_OS_SPECIFIC_BINARIES_PATH"/sysctl;

# list of flutter tools specific deps
FLUTTER_DEPS_PACKAGES="git rsync unzip"
# list of fastlane tools specific deps
FASTLANE_DEPS_PACKAGES="zip openssh curl"
# list of Nix packages to install
NIX_PACKAGES="darwin.shell_cmds ruby bash dart $FLUTTER_DEPS_PACKAGES $FASTLANE_DEPS_PACKAGES"

PROFILE="(version 1)
(debug deny)

;; by default deny everything
(deny default)

;; allow sending signals to itself and processes in the same group
(allow signal (target same-sandbox))

;; allow internet connections
(allow network-outbound)
(allow network-inbound)

;; lookup of IPC communications/messages like PowerManagement
(allow mach-lookup)

;; read POSIX shared memory
(allow ipc-posix-shm-read-data)
(allow ipc-posix-shm-read-metadata)

;; access to notifications
(allow ipc-posix-shm
       (ipc-posix-name \"apple.shm.notification_center\")
       (ipc-posix-name \"com.apple.AppleDatabaseChanged\"))

;; allow execution of programs
(allow process-exec)
(allow process-fork)

; Allow reading system information like #CPUs, etc.
(allow sysctl-read)

;; make FS read only
(allow file-read* (subpath \"/\"))

; Standard devices.
(allow file* (subpath \"/dev\"))

;; allow writes to temp directories
(allow file* (subpath \"/private/tmp\"))
(allow file* (subpath \"/private/var/folders\"))

;; allow writes to specific directories
(allow file* (subpath \"$WORKING_DIRECTORY\"))
(allow file* (subpath \"$SANDBOX_HOME\"))
(allow file* (subpath \"$XCODE_DERIVED_DATA_DIR\"))
(allow file* (subpath \"$XCODE_SIMULATOR_DEVICES_DIR\"))
(allow file* (subpath \"$XCODE_SIMULATOR_LOGS_DIR\"))
(allow file* (subpath \"$ORIGINAL_HOME_FLUTTER_CONFIG_DIR\"))
(allow file* (subpath \"$ORIGINAL_HOME_FVM_DIR\"))
(allow file* (subpath \"$ORIGINAL_KEYCHAIN_DIR\"))
(allow file* (path \"$ORIGINAL_SECURITY_PREFERENCES_FILE\"))
(allow file* (subpath \"$ORIGINAL_PROVISIONING_PROFILES_DIR\"))

;; uncomment to dump traces
;; (trace \"trace_dumps.sb\")
"

TMP_PROFILE_FILE="$SANDBOX_HOME/sandbox.sb"
echo "$PROFILE" > "$TMP_PROFILE_FILE"

# We use Nix to compute a PATH for the packages and then use it to emulate sandbox.
NIX_SHELL_PATH=$(nix-shell --packages ${NIX_PACKAGES} --pure --run "echo \$PATH")
GEM_PATH=$(nix-shell --packages ${NIX_PACKAGES} --pure --run "export HOME=$SANDBOX_HOME && echo \$(gem env | grep -e \"USER INSTALLATION DIRECTORY\" | cut -d : -f 2 | xargs)/bin")
PUB_CACHE_PATH=$SANDBOX_HOME/.pub-cache/bin;
SANDBOX_SHELL_PATH=$NIX_SHELL_PATH:$PUB_CACHE_PATH:$SANDBOX_OS_SPECIFIC_BINARIES_PATH:$GEM_PATH

# Usage: runInSandbox 'YOUR_BASH_COMMAND_AS_STRING'
runInSandbox() {
  COMMAND=$1;

  SET_SANDBOX_ENV_CMD="set -e && \
  export PATH=$SANDBOX_SHELL_PATH && \
  export HOME=$SANDBOX_HOME && \
  export FLUTTER_ROOT='$WORKING_DIRECTORY/.fvm/flutter_sdk' && \
  export GIT_SSH_COMMAND='ssh -o StrictHostKeyChecking=no'"

  sandbox-exec -f "$TMP_PROFILE_FILE" bash -c "$SET_SANDBOX_ENV_CMD && $COMMAND"
}

# Install fvm and corresponding flutter version
runInSandbox "dart pub global activate fvm && fvm install"

# Install ruby bundler and cocoapods
runInSandbox "gem install bundler:$BUNDLER_VERSION && gem install cocoapods --user-install"

# Run requested command
runInSandbox "$TARGET_COMMAND"
