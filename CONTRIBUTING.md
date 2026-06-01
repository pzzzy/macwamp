# Contributing

Thank you for considering a contribution.

## Development setup

```sh
swift build
swift run MacWamp
```

## Pull request checklist

- `swift build` passes
- changes are scoped and explained
- no third-party Winamp/source/skin assets are committed
- no build outputs, logs, credentials, or personal files are committed
- UI changes preserve integer scaling and nearest-neighbor pixel rendering

## Code style

- Prefer direct AppKit and small Swift files over framework-heavy abstractions.
- Preserve the classic pixel-coordinate model: hit tests and drawing should be easy to compare against reference coordinates.
- Add comments for non-obvious sprite-sheet coordinates or audio behavior.
