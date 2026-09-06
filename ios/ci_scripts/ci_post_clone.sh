#!/bin/sh

# Prepare Flutter and native iOS dependencies in Xcode Cloud's temporary
# build environment. This script runs after the repository is cloned.
set -e

cd "$CI_PRIMARY_REPOSITORY_PATH"

# Install the current stable Flutter SDK required to generate iOS build files.
git clone https://github.com/flutter/flutter.git --depth 1 -b stable "$HOME/flutter"
export PATH="$PATH:$HOME/flutter/bin"

# Fetch the iOS engine artifacts and resolve the versions locked in pubspec.lock.
# `flutter build --config-only` creates the CocoaPods plugin symlinks and
# generated iOS settings without compiling or signing an app.
flutter precache --ios
flutter pub get
flutter build ios --config-only --no-codesign --release

# Resolve the native plugin dependencies used by the Runner workspace.
if ! command -v pod >/dev/null 2>&1; then
  export HOMEBREW_NO_AUTO_UPDATE=1
  brew install cocoapods
fi
cd ios
pod install --repo-update
