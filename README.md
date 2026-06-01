# MacWamp

MacWamp is a native macOS / Apple Silicon experiment that recreates the feel of the classic Winamp interface using AppKit and AVFoundation.

The project is intentionally small and hackable: it is a Swift Package executable, not a large Xcode workspace. It draws the player, equalizer, and playlist windows manually in a classic pixel-art coordinate system, then uses native macOS audio APIs for local playback.

## Current status

MacWamp is an early public release / proof of concept. It already includes:

- native borderless AppKit windows
- classic 275 x 116 main player layout at 2x integer pixel scale
- transport controls, position, volume, balance, shuffle, repeat, eject/open
- accurate bitrate / sample-rate / mono-stereo metadata via AudioToolbox
- AVAudioEngine playback
- a real AVAudioUnitEQ-backed equalizer window
- playlist window with add/remove/select/clear, drag-and-drop files/folders, recursive folder import, scrolling, and double-click-to-play
- keyboard shortcuts for common Winamp-style controls
- optional local skin asset loading for private compatibility work

## Legal / asset notice

This repository does not redistribute Winamp source code, Winamp bitmap resources, or Winamp trademarks.

During development, the original Winamp source release and the Linamp community remake were used as local references for behavior, architecture, and coordinate research. Their code and assets are not vendored here.

The public repository is source-only and ships with a programmatic fallback skin so it can build and run without proprietary or ambiguously licensed assets. For private/local research, you may provide your own compatible classic skin bitmap sheets under:

```text
Sources/MacWamp/Resources/WinampClassic/
```

Expected optional filenames:

```text
main.bmp
cbuttons.bmp
titlebar.bmp
numbers.bmp
text.bmp
volume.bmp
balance.bmp
posbar.bmp
playpaus.bmp
monoster.bmp
shufrep.bmp
pledit.bmp
eqmain.bmp
```

Only add assets that you have the right to use and distribute. Do not open a pull request that includes third-party skin files unless their license clearly permits redistribution.

## Requirements

- macOS 14 or newer
- Apple Silicon or Intel Mac supported by the Swift toolchain
- Xcode command line tools / Swift 6+

Check your toolchain:

```sh
swift --version
```

## Fully automated local setup with classic assets

For a local install that imports compatible classic bitmap sheets automatically, run:

```sh
scripts/setup-assets.sh
```

For unattended setup after you have reviewed and accepted the upstream Winamp licensing terms:

```sh
scripts/setup-assets.sh --accept-winamp-license --yes
```

To use an existing local Winamp checkout instead of downloading one:

```sh
scripts/setup-assets.sh --source /path/to/winamp --accept-winamp-license
```

The setup wizard imports only into your local working copy. Imported `.bmp` files are ignored by git and are not redistributed by this repository.

## Build

```sh
swift build
```

## Run

Launch without a file:

```sh
swift run MacWamp
```

Launch with an audio file or a folder of audio files:

```sh
swift run MacWamp /path/to/song.mp3
swift run MacWamp /path/to/music-folder
```

Launch with the EQ and resizable playlist windows already open:

```sh
swift run MacWamp /path/to/song.mp3 --show-eq --show-playlist
```

Inside the app:

- click eject/open to choose an audio file
- drag an audio file or folder onto the main or playlist window
- drag the playlist lower-right grip to resize it and show more rows
- double-click a playlist row to play it
- use the main EQ and PL buttons to show/hide auxiliary windows

## Keyboard shortcuts

| Key | Action |
| --- | --- |
| Space | Pause/resume |
| O | Open file |
| X | Play |
| C | Pause/resume |
| V | Stop |
| Z | Previous playlist item |
| B | Next playlist item |
| S | Shuffle |
| R | Repeat |
| E | Toggle equalizer |
| L | Toggle playlist |
| Q | Quit |

## Architecture

```text
Package.swift
Sources/MacWamp/
  App.swift            Application delegate, controller, playback, playlist state
  WinampView.swift     Main player rendering and hit-testing
  AuxWindows.swift     Equalizer and playlist windows
  WinampSkin.swift     Sprite-sheet drawing and fallback skin generation
```

Important implementation choices:

- AppKit is used directly rather than SwiftUI so the UI can keep the classic pixel coordinate model.
- Rendering uses flipped views, integer scaling, and nearest-neighbor interpolation.
- Hit tests are manual rectangles in original-style pixel coordinates.
- Playback uses AVAudioEngine + AVAudioPlayerNode + AVAudioUnitEQ.
- Audio metadata comes from AudioToolbox when possible, with file-size fallback for bitrate.

## Quality checks

Run before submitting changes:

```sh
swift build
swift package dump-package >/tmp/macwamp-package.json
```

A GUI smoke test can be done locally with a short sample file:

```sh
swift run MacWamp /path/to/sample.mp3 --show-eq --show-playlist
```

## Roadmap

- exact clean-room skin art or explicit support for user-installed skins
- app bundle packaging and notarization
- more faithful Winamp EQ curve matching
- spectrum analyzer driven from FFT rather than metering approximation
- playlist save/load formats
- window snapping and shade modes
- automated UI snapshot tests

## Contributing

Contributions are welcome, especially careful macOS/AppKit fidelity fixes. Please keep the legal boundary clean: do not commit third-party Winamp assets, proprietary skin files, or copied code from sources whose license does not allow redistribution.

## License

MacWamp source code in this repository is licensed under GPL-3.0-or-later. See [LICENSE](LICENSE).
