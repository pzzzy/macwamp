# Architecture

MacWamp is a compact AppKit program organized around a single main-actor controller.

## Controller

`WinampController` owns playback, metadata, playlist state, EQ state, and auxiliary-window visibility.

Playback uses:

- `AVAudioEngine`
- `AVAudioPlayerNode`
- `AVAudioUnitEQ`
- `AudioToolbox` for bitrate/sample-rate/channel metadata

The controller exposes small state fields; views subscribe through change handlers and redraw themselves.

## Views

`WinampView` draws the main player and maps mouse events to classic hit rectangles.

`EqualizerView` draws a fixed-size classic equalizer and maps sliders/buttons to `AVAudioUnitEQ` state.

`PlaylistView` draws the playlist window and handles drag/drop, double-click playback, add/remove/select/clear, and scrolling.

## Skin loading

`WinampSkin` loads optional bitmap sheets from the SwiftPM resource bundle. If a sheet is absent, `SpriteSheet` creates a simple generated fallback image. This keeps the public repository buildable and runnable without redistributing third-party artwork.
