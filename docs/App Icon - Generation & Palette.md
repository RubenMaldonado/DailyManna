### Daily Manna App Icon: Generation, Palette, and Usage

This document explains how the app icon is designed, where the source files live, and how to regenerate all iPhone, iPad, and macOS icon sizes for the project.

### Concept

- **Brand idea**: Daily Manna = daily bread + tasks/actions
- **Icon motif**: a warm gradient tile with a bread loaf and a carved checkmark, plus subtle scoring lines on the loaf

### Source Files

- Script: `scripts/generate_app_icons.swift`
- Palette: `art/app_icon_palette.json`
- SVG master (reference artwork): `art/AppIcon/DailyManna-AppIcon.svg`
- Output directory: `DailyManna/Assets.xcassets/AppIcon.appiconset`

The asset catalog `AppIcon.appiconset/Contents.json` is already configured to reference the generated filenames and is selected in the Xcode build setting `ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon`.

### Regenerate Icons (one command)

From the project root:

```bash
make icons
```

This runs the generator with the configured palette and writes all required images into `AppIcon.appiconset`.

### Regenerate Icons (manual invocation)

```bash
swift "$(PWD)/scripts/generate_app_icons.swift" \
  --config "$(PWD)/art/app_icon_palette.json" \
  "$(PWD)/DailyManna/Assets.xcassets/AppIcon.appiconset"
```

Arguments:

- `--config <path>`: optional; JSON palette with brand colors (see below)
- `<output_appiconset_directory>`: where PNGs are written (the app icon asset set)

### Palette Configuration

Edit `art/app_icon_palette.json` to adjust the icon colors. Hex values may be 6-digit (RGB) or 8-digit (RGBA). Example:

```json
{
  "default": {
    "backgroundTop": "#FFF3CC",
    "backgroundBottom": "#F1A23B",
    "bread": "#945C2A",
    "breadShadow": "#0000002E",
    "checkmark": "#FFFFFF"
  },
  "dark": {
    "backgroundTop": "#26221D",
    "backgroundBottom": "#141311",
    "bread": "#D19A5C",
    "breadShadow": "#0000004D",
    "checkmark": "#FFFFFF"
  },
  "tinted": {
    "backgroundTop": "#F8E7C2",
    "backgroundBottom": "#D79B52",
    "bread": "#7E5128",
    "breadShadow": "#00000029",
    "checkmark": "#FFFFFF"
  }
}
```

- The generator renders with `default` for most sizes and produces additional 1024px iOS marketing variants for `dark` and `tinted` to match the asset catalog appearances.

### Sizes Generated

- iPhone: 20@2x, 20@3x, 29@2x, 29@3x, 40@2x, 40@3x, 60@2x, 60@3x
- iPad: 20@1x, 20@2x, 29@1x, 29@2x, 40@1x, 40@2x, 76@1x, 76@2x, 83.5@2x
- iOS Marketing: 1024 (default, dark, tinted)
- macOS: 16, 32, 128, 256, 512 @1x and @2x

The asset catalog `Contents.json` has matching entries with filenames, and the project is configured to use `AppIcon` for the app target, so these will be included at build time.

### Verifying in Xcode

1. Open the project, select the app target.
2. Build Settings → ensure `ASSETCATALOG_COMPILER_APPICON_NAME` is `AppIcon`.
3. In the asset catalog, open `AppIcon` and confirm slots show the generated images.
4. Clean build folder if images don’t appear after regeneration.

### Troubleshooting

- If the command fails, check that the Swift toolchain is available in PATH (`swift --version`).
- Ensure paths are quoted if the project path includes spaces.
- If Xcode shows old icons, try Product → Clean Build Folder and rebuild.
- If macOS icons look soft, re-run `make icons` after any palette or script changes.

### Notes

- The SVG master is a reference. The shipped PNGs are programmatically rendered by the Swift script to guarantee crisp edges at every size.
- Colors can be aligned with design tokens in `DailyManna/DesignSystem/Tokens/Colors.swift` by updating the palette JSON to match your brand choices.


