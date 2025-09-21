## Liquid Glass — Implementation Plan (iOS 26 / macOS 26)

### Goals
- Align chrome and overlays with Liquid Glass while preserving text legibility and performance.
- Keep content surfaces opaque by default for readability, with tasteful glass accents.
- Respect Reduce Transparency/Motion; provide in-app toggles.

### Feature flag
- `liquidGlassEnabled` (default OFF). Roll out via TestFlight.

### Phase 1 — Tokens and utilities
- Add `DesignSystem/Tokens/Materials.swift`:
  - Map `glass.chrome`, `glass.overlay`, `glass.tint.{neutral,primary,danger}`.
  - Provide platform-conditional mapping to Liquid Glass; fallback to SwiftUI `.ultraThinMaterial`/`.regularMaterial`.
- Extend `SurfaceStyle.Kind`:
  - Add `.glassChrome`, `.glassOverlay`, `.glassContent` (routes to opaque by default).
- Add `DesignSystem/Utilities/GlassEffects.swift`:
  - Hairline stroke helper, micro specular highlight overlay, press-state animation that respects Reduce Motion.

### Phase 2 — Chrome and overlays
- Apply `.glassChrome` to navigation/toolbars/tab bars on iOS/macOS where appropriate.
- Overlays (sheets/popovers): use `.glassOverlay` with adaptive dim; respect `Reduce Transparency`.

### Phase 3 — Components
- Buttons: add `GlassSecondaryButtonStyle`, `GlassTertiaryButtonStyle` (translucent background, 1px outline, specular on press). Keep `PrimaryButtonStyle` solid.
- Chips/Badges: frosted backgrounds with adaptive tints; maintain min contrast, respect accessibility.
- TaskCard: keep opaque base; add lifted/press states with subtle inner highlight, optional tiny translucency only if contrast holds.

### Phase 4 — Screens (behind feature flag)
- Board: column headers and top chrome use glass; columns remain `.content`. Verify drag-and-drop visibility.
- Task List & Detail: chrome to glass; chips frosted; content surfaces remain opaque.

### Phase 5 — Preferences & accessibility
- Settings toggle: “Reduce Glass Effects” (forces `.solidFallback` routes).
- Ensure Reduce Motion disables press specular animations.
- Increase Contrast thickens hairlines/outlines and boosts tint opacity.

### Phase 6 — Performance & QA
- Audit live materials in scrolling areas; cap to chrome/overlays.
- Use Instruments (Core Animation) to detect offscreen/rasterization hotspots.
- Visual regression across Light/Dark, wallpapers, Reduce Transparency/Motion ON/OFF.

### File-level checklist
- Tokens & Utilities:
  - [ ] Add `DesignSystem/Tokens/Materials.swift`
  - [ ] Add `DesignSystem/Utilities/GlassEffects.swift`
  - [ ] Update `DesignSystem/Components/SurfaceStyle.swift` (new kinds)
- Components:
  - [ ] Update `DesignSystem/Components/Buttons.swift` (glass styles)
  - [ ] Update `DesignSystem/Components/TaskCard.swift` (lifted/press states)
  - [ ] Update `DesignSystem/Components/Banner.swift` & chips to frosted
- Screens:
  - [ ] Apply glass to chrome in primary views (Board, Task List, Task Detail)
- Settings:
  - [ ] Add toggles for Glass Effects and Motion
- QA:
  - [ ] Snapshot and video comparisons; accessibility sweeps

### Rollout
- Dev → TestFlight (10–20%) → 100%. Monitor crash/ANR, frame pacing, user feedback about comfort and readability.


