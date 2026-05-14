# AppMixer

A lightweight per-app volume mixer for macOS — adjust or mute the volume of
individual applications, similar to SoundSource.

No kernel extension, no audio driver to install. AppMixer uses the modern
Core Audio process-tap API (macOS 14.2+) to capture an app's audio, mute its
original output, and re-inject it through a private aggregate device at the
volume you choose.

## Features

- Per-app volume sliders (0–100%)
- Per-app mute
- Menu bar item with a popover
- Global hotkey (`⌃⌥⌘M`) to summon the control panel — handy when the menu bar
  icon is hidden behind the notch
- Apps at 100% are left completely untouched (no tap, no overhead)

## Requirements

- macOS 15 or later
- Swift 6 toolchain (`swift build`)

## Build

```sh
./build.sh
```

This compiles the project and assembles `AppMixer.app` in the repo root, then
ad-hoc code-signs it. Move the bundle to `/Applications` if you like, and add it
to **System Settings → General → Login Items** to launch it at login.

## Usage

1. Launch `AppMixer.app`. A control panel window appears on first launch.
2. Click the menu bar icon, or press `⌃⌥⌘M`, to show the panel again.
3. Drag a slider or hit the mute button next to any app.

The first time you adjust an app's volume, macOS asks for audio-capture
permission — allow it. If you miss the prompt, grant it under
**System Settings → Privacy & Security**.

## How it works

- `AudioProcessController` enumerates audio processes via
  `kAudioHardwarePropertyProcessObjectList` and maps them to running apps.
- `ProcessTap` creates a `CATapDescription` (with `muteBehavior =
  .mutedWhenTapped`), builds a private aggregate device containing the tap and
  the real output device, and installs a realtime `AudioDeviceIOProc` that
  scales the tapped audio by the chosen gain.
- `AudioManager` ties it together and only keeps a tap alive while an app is
  below 100%.

## Limitations

- Assumes the tap and output device use a Float32 stream format (true in the
  vast majority of cases). Unusual audio devices may need format conversion.
- Volume settings are kept in memory only; they are not persisted across
  launches.

## License

MIT — see [LICENSE](LICENSE).
