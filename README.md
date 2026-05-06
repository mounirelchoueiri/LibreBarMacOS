# LibreBar

Open-source macOS menu bar app for real-time glucose monitoring via LibreLinkUp.

`LibreBar` is a lightweight menu bar utility that connects to your LibreLinkUp account and displays your latest glucose reading, trend arrow, and history graph directly in the macOS menu bar. It is designed to be simple, fast, and always visible — no need to reach for your phone to check your glucose.

## What It Does

LibreBar gives you a persistent glucose reading in your menu bar with a popover for detailed information.

Core workflow:

1. Launch LibreBar.
2. Enter your LibreLinkUp credentials in Settings.
3. Your current glucose reading and trend arrow appear in the menu bar.
4. Click the menu bar item to see detailed info: color-coded reading, mini graph, rate of change, and time since last reading.
5. LibreBar refreshes automatically every 60 seconds.

Everything is built around the idea that checking your glucose should be instant and effortless — a glance at the menu bar, nothing more.

## Features

- Live glucose reading and trend arrow in the macOS menu bar
- Color-coded readings in the popover: green for in-range, orange for high/low, red for urgent
- Mini graph with selectable time range (1 hour, 3 hours, 12 hours)
- Rate of change display (mmol/L or mg/dL per minute)
- Time since last reading with stale data warning (15+ minutes)
- Toggle between mmol/L and mg/dL units
- Customizable target range thresholds via sliders
- Multiple LibreLinkUp connection support — choose which person to monitor
- Automatic region detection for the LibreLinkUp API
- Launch at login support
- Secure credential storage via macOS Keychain
- Menu bar utility design — no dock icon, no clutter

## Privacy

LibreBar communicates only with the official LibreLinkUp API (libreview.io).

- Credentials are stored locally in the macOS Keychain
- No analytics, no telemetry, no third-party services
- No data is stored or transmitted beyond what is required to fetch your glucose readings

## Tech Stack

- Swift
- SwiftUI
- AppKit
- Swift Charts
- CryptoKit
- ServiceManagement
- macOS Keychain Services

## Installation

### Requirements

- macOS 14.0 or later
- A LibreLinkUp account with at least one active connection (someone sharing their Libre sensor data with you)

### Download

1. Download **LibreBar-1.0.dmg** from the [latest release](https://github.com/mounirelchoueiri/LibreBarMacOS/releases/latest)
2. Open the DMG
3. Drag **LibreBar** to **Applications**
4. Launch LibreBar from Applications
5. Click `--` in the menu bar, then click **Settings**
6. Enter your LibreLinkUp email, password, and select your region
7. Click **Save & Connect**

### Building from Source

If you prefer to build the app yourself:

1. Clone the repository
2. Open `LibreBar/LibreBar.xcodeproj` in Xcode 15 or later
3. Build and run the app

### Supported Regions

United States, Canada, Europe, Germany, France, Australia, Asia Pacific, and Japan. The app also auto-detects and redirects to the correct region if needed.

## Open Source License

This project is licensed under the **MIT License**.

You are free to use, modify, and distribute this software. See the [LICENSE](LICENSE) file for details.

## Why Open Source?

Glucose monitoring tools should be transparent and accessible to everyone. If you want to tweak the refresh interval, add new features, change the graph style, or integrate with a different data source, you can.

## Notes

- LibreBar depends on the unofficial LibreLinkUp API, which is maintained by Abbott. API changes may require updates to the app
- The app requires an active internet connection to fetch glucose data
- Refresh interval is 60 seconds, which aligns with how frequently LibreLinkUp updates readings

## Credits

Built by Mounir El-Choueiri.

Made with love in Canada.
