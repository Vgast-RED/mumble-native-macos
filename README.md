# Mumble Native for Apple Silicon

One-click installer that builds **official Mumble v1.6.870** as native **arm64** (Qt6, no Rosetta) and writes a shareable DMG.

Verified on Mac mini M4, macOS 27.0.

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/Vgast-RED/mumble-native-macos/main/install.sh | bash
```

Or download `install.sh`, then Control-click → Open.

First run takes 15–40 minutes (Homebrew + Qt6 + compile). After that:

- `/Applications/Mumble.app`
- `~/Desktop/Mumble-1.6.870-arm64.dmg` — send this to friends. They drag Mumble into Applications. No compile.

## Requirements

- Apple Silicon (M1–M4). Intel is refused.
- About 8 GB free disk
- Internet
- Admin password if Homebrew / Xcode CLT is missing

## After install

1. Control-click Mumble → Open (ad-hoc signature, not notarized).
2. Grant microphone when asked.
3. Activity Monitor → Kind **Apple**.

Game overlay is disabled on ARM by upstream Mumble.

## What it is not

Not an official Mumble binary. Not Apple-signed. Not a patched 1.5/Qt5 bundle.

Sources: [mumble-voip/mumble](https://github.com/mumble-voip/mumble) (BSD).
