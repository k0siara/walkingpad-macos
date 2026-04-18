# WalkFlow

Unofficial native macOS app and menu bar remote for WalkingPad / Kingsmith treadmills.

## Features

- Native SwiftUI macOS app
- Menu bar quick controls
- Bluetooth Low Energy connection to WalkingPad treadmills
- Start / stop belt
- Speed up / down in 0.5 km/h steps
- Favorite speed presets

## Install

### Option 1: Release build

1. Download the latest `WalkFlow.app` from GitHub Releases.
2. Move `WalkFlow.app` to `/Applications`.
3. Open the app and allow Bluetooth access when macOS asks.
4. Wake the treadmill and close the official WalkingPad mobile app before connecting.

### Option 2: Build from source

1. Clone the repository.
2. Open [WalkFlow.xcodeproj](WalkFlow.xcodeproj) in Xcode.
3. Select the `WalkFlow` scheme.
4. Build and run the app on macOS.
5. Allow Bluetooth access on first launch.

## Notes

- This is an unofficial project.
- WalkingPad treadmills generally accept only one active Bluetooth connection at a time.
- If the treadmill is not visible, wake it first and make sure no phone app is already connected.