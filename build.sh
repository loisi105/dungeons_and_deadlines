#!/bin/zsh
# Build (or test with: ./build.sh test) the app for the iOS simulator.
export DEVELOPER_DIR=${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}
ACTION=${1:-build}
xcodebuild $ACTION -project DungeonsAndDeadlines.xcodeproj -scheme DungeonsAndDeadlines \
  -destination "platform=iOS Simulator,name=${SIMULATOR:-iPhone 18 Pro}" \
  -clonedSourcePackagesDirPath build/SourcePackages -derivedDataPath build/DerivedData "${@:2}"
