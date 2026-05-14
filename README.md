# AppMixer

A lightweight per-app volume mixer for macOS — adjust or mute the volume of
individual applications, similar to SoundSource.

No kernel extension, no audio driver to install. AppMixer uses the modern
Core Audio process-tap API (macOS 14.2+) to capture an app's audio, mute its
original output, and re-inject it through a private aggregate device at the
volume you choose.

## Features

- Per-app volume sliders (0–100%) and per-app mute
- Per-app output device routing — send each app to a different output device
- Settings persist across launches (keyed by bundle ID)
- Optional global volume keys that adjust the frontmost app's volume
- Menu bar item with a popover
- Global hotkey (`⌃⌥⌘M`) to summon the control panel — handy when the menu bar
  icon is hidden behind the notch
- Apps left at 100% on the default device are completely untouched (no tap,
  no overhead)

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

To route an app to a specific output device, use the device menu in its row.

The **volume keys** option (bottom of the panel) makes the hardware volume keys
control whichever app is frontmost. It needs Accessibility permission — grant it
under **System Settings → Privacy & Security → Accessibility**, then re-enable
the option.

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
  vast majority of cases). Unusual audio devices may need format conversion;
  AppMixer logs a warning when it sees a non-float format.
- No per-app EQ or audio effects.

## License

MIT — see [LICENSE](LICENSE).
