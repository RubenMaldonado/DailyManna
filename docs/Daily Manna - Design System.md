# **Daily Manna — Design System v1.2 (Modern SwiftUI-Only Architecture)**

## **1\) Design philosophy & Modern SwiftUI Architecture**

### **SwiftUI-Only Decision (v1.2)**
**Architecture Change**: Migrated from UIKit-dependent system colors to a pure SwiftUI implementation with custom design tokens. This ensures:
- **No UIKit dependencies**: Modern SwiftUI-only codebase  
- **Brand consistency**: Full control over colors and theming
- **Performance**: No UIKit bridging overhead
- **Future-ready**: Easier to maintain and extend

### **Design Philosophy**
**Clarity through structure → Depth with restraint.** Keep your minimalist, opinionated buckets model. Use depth (translucency, parallax, blur) **only** to clarify hierarchy—never as decoration. Custom design tokens provide built-in accessibility compliance without system dependencies.

* **Subtraction as a feature:** Default to fewer affordances on each surface; promote actions contextually (hover/right-click on macOS, swipe on iOS).

* **Opinionated framework \+ flexible tags:** Buckets drive navigation; Labels remain cross-cuts.

* **Delight, not distraction:** Micro-interactions \< 200ms; spring animations only where they signal cause→effect.

---

## **2\) Surface & Material model (new)**

Prepare for Liquid Glass by **abstracting surfaces** behind tokens and policies. Ship today with SwiftUI `Material`/opaque surfaces; flip to Liquid-Glass materials when available.

**Surface tokens**

* `surface/background` — base canvas; opaque system background.

* `surface/content` — list rows, cards; 96–100% opaque (ensures text contrast).

* `surface/chrome` — toolbars, tab bars, filter bars; **translucent** candidate (Liquid-Glass later).

* `surface/overlay` — sheets, popovers; dimmed/backdrop-blurred layer; enforce min contrast.

* `surface/elevated` — menus, context panels; slightly higher blur/elevation.

* `surface/solidFallback` — used automatically when Reduce Transparency is ON.

**Rules**

* Text must meet **≥ 4.5:1** contrast (normal) and **≥ 3:1** for large titles over any live background.

* If live wallpaper/content breaks contrast, auto-apply a **backdrop dim** (e.g., 8–12% black in Light, 12–16% white in Dark) beneath text.

* Translucency belongs to **chrome** (navigation, filters), not content.

### **2.1 Liquid Glass (iOS 26 / macOS 26)**

**Principles**

- Use translucent materials to clarify hierarchy and preserve context.
- Prefer glass for chrome (navigation, filters) and overlays; keep dense text on opaque content surfaces.
- Always respect Reduce Transparency/Motion and maintain minimum contrast.

**Material mapping**

- `chrome` → Liquid Glass Chrome (thin). Fallback: `.ultraThinMaterial` with backdrop dim when needed.
- `overlay` → Liquid Glass Overlay (regular) + adaptive dim. Fallback: `.regularMaterial` + dim.
- `content` → Opaque surface for readability (no glass).

**Tokens to add**

- `material.glass.chrome`, `material.glass.overlay` with platform-conditional mapping.
- `material.glass.tint.{neutral,primary,danger}` (adaptive alpha for stable contrast across modes).
- `stroke.hairline` (1px) and `specular.micro` for subtle press/hover highlight.

**Accessibility**

- When `Reduce Transparency` is ON, force `surface/solidFallback` and disable specular effects.
- Auto-apply backdrop dim under glass if dynamic backgrounds reduce contrast.

**Performance**

- Avoid deep nesting of live materials inside scrolling content.
- Prefer glass in headers, footers, toolbars, overlays; keep list rows/cards opaque.

**Developer note**

- Gate Liquid Glass behind a `liquidGlassEnabled` feature flag and platform checks; use SwiftUI `Material` as fallback.

---

## **3\) Color system (tokenized)**

Keep brand colors, but route all usage through **semantic roles** so system modes, accessibility, and materials render correctly.

**Semantic roles**

* `text/primary`, `text/secondary`, `text/inverse`

* `tint/primary` (brand blue), `tint/secondary` (brand purple)

* `bg/base`, `bg/secondary`, `bg/tertiary`

* `state/success`, `state/warning`, `state/danger`

* `badge/neutral`, `badge/attention`

**Brand mapping (SwiftUI-Only Implementation)**

* `tint/primary` → `Color.blue` (SwiftUI native)

* `tint/secondary` → `Color.orange` (SwiftUI native)

* `bg/base` → `Color.white` (custom light theme)

* `bg/surface` → `Color.gray.opacity(0.05)` (custom surface)

* **Text colors**: Custom brand-aligned colors using SwiftUI `Color` primitives, ensuring accessibility compliance without UIKit dependencies.

---

## **4\) Typography (system-native \+ variable)**

* Use **SF Pro** / **SF Compact** with Dynamic Type.

* Enable **monospaced digits** for counts (badges, totals).

* Platform scale: macOS slightly denser; iOS a notch larger for touch.

* Roles: `TitleXL` (screen title), `Title`, `Headline`, `Body`, `Footnote`, `Caption`. Each role has min/max line heights and truncation rules (1→2 lines before ellipsis).

---

## **5\) Spacing, layout & density**

* **4-pt grid** with standard steps: 4/8/12/16/24/32.

* **Touch targets ≥ 44×44pt**; macOS click targets ≥ 28×28pt.

* **List density**: iOS 56–60pt row height; macOS 44–48pt by default, with a “Comfort/Dense” toggle in app settings.

* **Split views**: iPad/macOS use Sidebar → Content → Detail; collapse gracefully on iPhone.

---

## **6\) Iconography (SF Symbols first)**

* Prefer **SF Symbols** (monochrome) with a **gradient accent** only where contrast is guaranteed (feature-flagged).

* Keep your minimalist line-style for custom metaphors; match SF stroke weights.

* Provide **filled** variants for selected/active states; never rely on color alone.

---

## **7\) Interaction & motion (guardrails)**

* **Completion**: subtle scale+fade on check, haptic on iPhone, soundless on macOS.

* **Navigation**: contextual transitions (slide/push on iOS; fade/scale on macOS).

* **Drag & drop**: bucket reassign with lift \+ target highlight.

* **Reduce Motion** → cross-fade, no spring.

* All animations **≤ 200ms** (micro) and **≤ 350ms** (page/sheet).

---

## **8\) Component library (spec refresh)**

### **8.1 Task Cell**

* **Content slots**: status, title (1–2 lines), caption (due), labels (wrap), overflow menu.

* States: default, hover (macOS), pressed (iOS), completed (dimmed text \+ check fill), syncing (subtle spinner inline).

* **Swipe (iOS)**: Complete / Move / Label. **Right-click (macOS)**: same actions.

### **8.2 Bucket Header**

* Title \+ count badge; sticky at top; optional translucency (chrome surface rules).

* Context menu: sort, filter labels, show completed.

### **8.3 Label Chip**

* Pill with min 28pt height; contrast-aware foreground.

* Selected state: raise elevation \+ stronger outline (works in monochrome).

### **8.4 Composer (Quick Add)**

* **Phase-1 (no NLP)**: Title, bucket picker, labels pills, due date.

* Keyboard: `⌘N` (macOS), `Return` to save, `⌘⇧L` to focus Labels.

* **Phase-2**: optional NLP field replaces/prefills the structured fields.

### **8.5 Chrome (Toolbar/Tab bar/Sidebar)**

* Candidates for Liquid-Glass material.

* Provide `SurfaceStyle.chrome` token to swap material when API is available; otherwise use `ultraThinMaterial` with auto-contrast guard.
* Add a 1px hairline bottom stroke for separation; increase to 2px when Increase Contrast is ON.

### **8.6 Overlays (Sheet/Popover/Toast)**

* Use sheet for compose; popover for quick edits; non-blocking **banner** for sync status.

* Enforce overlay contrast with automatic backdrop dim.
* Use Liquid Glass overlay material with adaptive dim on iOS 26/macOS 26; fallback to `.regularMaterial`.

### **8.7 Widgets**

* Small/Medium: per-bucket counts and “Add” intent.

* Respect variant backgrounds; lock text to `text/inverse` when on photos.

---

## **9\) Accessibility (hard requirements)**

* **Contrast:** ≥ 4.5:1 for text; 3:1 for large headings & icons conveying state.

* **Transparency:** When **Reduce Transparency** is ON, force `surface/solidFallback`.

* **Motion:** Respect **Reduce Motion**; no parallax or spring.

* **VoiceOver:** Rotor actions on cells (Complete, Move to Bucket, Add Label).

* **Focus** (macOS): clear focus rings; logical tab order; `ESC` closes panels.

---

## **10\) Token set (developer-ready)**

Use a single source of truth (JSON/Swift enum) to drive SwiftUI.

{

  "color": {

    "text.primary": "Label",

    "text.secondary": "SecondaryLabel",

    "tint.primary": "\#096682",

    "tint.secondary": "\#4E1578",

    "state.success": "SystemGreen",

    "state.danger": "SystemRed"

  },

  "surface": {

    "background": { "type": "opaque", "material": "systemBackground" },

    "content":    { "type": "opaque", "material": "secondarySystemBackground" },

    "chrome":     { "type": "translucent", "material": "thin", "lgCandidate": true },

    "overlay":    { "type": "translucent", "material": "regular", "dim": 0.12 },

    "solidFallback": { "type": "opaque", "material": "systemBackground" }

  },

  "radius": { "sm": 10, "md": 14, "lg": 22 },

  "spacing": { "xs": 4, "sm": 8, "md": 12, "lg": 16, "xl": 24 },

  "elevation": { "base": 0, "raised": 1, "overlay": 2 }

}

**SwiftUI-Only Implementation (v1.2):**

```swift
struct SurfaceStyle: ViewModifier {
    enum Kind { case background, content, chrome, overlay, solidFallback }
    
    var kind: Kind
    
    func body(content: Content) -> some View {
        switch kind {
        case .background:
            content.background(Colors.background)
        case .content:
            content.background(Colors.surface)
        case .chrome:
            content.background(Colors.surfaceVariant)
        case .overlay:
            content.background(Colors.surface.opacity(0.95))
        case .solidFallback:
            content.background(Colors.background)
        }
    }
}

extension View {
    func surfaceStyle(_ kind: SurfaceStyle.Kind) -> some View {
        modifier(SurfaceStyle(kind: kind))
    }
}
```

**Benefits of SwiftUI-Only Approach:**
- No UIKit dependencies or system material bridging
- Consistent brand colors across all platforms  
- Full control over appearance and theming
- Better performance without UIKit bridging
- Simplified accessibility testing with known color values

*When Liquid Glass APIs are available*, you’ll flip the `.thinMaterial`/`.regularMaterial` branches to the new materials under a single feature flag. Centralize mapping in a `Materials` utility so only one implementation point changes.

---

## **11\) States: loading / empty / error / offline**

* **Loading**: skeleton rows (no shimmer if Reduce Motion).

* **Empty**: calm illustrations \+ one primary CTA (Add task).

* **Error**: in-place notice with retry; never modal-block.

* **Offline**: non-blocking banner; keep actions available; queue sync.

---

## **12\) Governance & delivery**

* Version the DS (`DS-1.1`) with a **changelog**.

* Token changes require **visual regression** across Light/Dark, Standard/Simplified, and with Reduce Transparency/Motion.

* Ship a **SwiftUI Preview Catalog** (all components in all states) as your design QA harness.

