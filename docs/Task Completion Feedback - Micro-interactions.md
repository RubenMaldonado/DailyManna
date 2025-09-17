### Task Completion Feedback: Micro‑interactions, Haptics, and Clarity

#### Goals
- Improve confidence that a task was completed successfully.
- Make the interaction delightful yet fast, lightweight, and accessible.
- Keep behavior consistent across list, board, and other task surfaces.

#### Problems Today
- Small hit target (28–32 pt) makes the check hard to tap; HIG recommends 44x44.
- Tasks can disappear abruptly when filters hide completed items.
- Visual change is subtle; feedback can feel delayed or inconsistent.

#### Design Principles
- Immediate, multi‑sensory confirmation (visual + haptic [+ optional sound]).
- Brief, springy animations (150–250 ms), respectful of Reduce Motion.
- Consistency via a reusable design‑system component.
- Smooth removal from lists, avoiding surprise “teleport” disappearance.

#### Solution Overview
1) Reusable `CompletionCheck` component
   - 44x44 tappable area, SF Symbol state swap (circle → checkmark.circle.fill).
   - iOS 17+: `.contentTransition(.symbolEffect(.replace))` and `.symbolEffect(.bounce, value:)`.
   - Light spring scale for older OS / Reduce Motion fallback.
   - Haptic confirmation with `.sensoryFeedback(.success, trigger:)` (iOS 17+) or existing `Haptics` helper.
   - Optional, user‑controllable completion sound (off by default).

2) Integrations
   - Replace inline checkmark `Button` in `TaskCard` and `TasksListRowView` with `CompletionCheck`.
   - Keep existing `onToggle` callbacks; wrap local changes in animation-friendly transitions.

3) List/Board row transitions
   - Apply `.transition(.asymmetric(insertion: .scale.combined(with: .opacity), removal: .move(edge: .trailing).combined(with: .opacity)))` to task rows/cards.
   - Slightly delay the filtered removal (~0.2 s) so the check animation reads before the item leaves.

4) Settings
   - Add toggles: “Completion haptic” (default on) and “Completion sound” (default off).
   - Respect system settings (silent mode, Reduce Motion) and provide sensible fallbacks.

#### Accessibility
- 44x44 minimum hit area; clear `accessibilityLabel` and `accessibilityValue`.
- Respect `Reduce Motion` to disable bounce/scale and use only symbol replacement + haptic.
- VoiceOver announcements remain concise: “Mark complete/Mark incomplete.”

#### Implementation Notes
- Component: `DesignSystem/Components/CompletionCheck.swift`
  - Props: `isCompleted: Bool`, `action: () -> Void`.
  - Uses `@AppStorage("completionHapticEnabled")` and `@AppStorage("completionSoundEnabled")`.
  - iOS 17+: `.sensoryFeedback(.success, trigger: isCompleted && hapticEnabled)` and symbol effects.
  - iOS < 17: fallback to `Haptics.lightTap()` and spring scale.
  - Optional sound via `AudioServicesPlaySystemSound` (short, subtle), behind toggle.

- Integrations:
  - `TaskCard` and `TasksListRowView` swap their checkmark buttons for `CompletionCheck`.
  - Add `.transition` on the card/row to animate filtered removal.

- Settings:
  - `SettingsView` adds a “Feedback” section with completion haptic and sound toggles (`@AppStorage`).

#### QA Checklist
- Reduce Motion on/off: symbol replacement only vs. bounce/scale.
- Silent mode: no sound even if enabled.
- VoiceOver: labels/values and rotor actions remain correct.
- Rapid tapping: no jank; no duplicate toggles.
- Filters that hide completed items: check animation visible before removal.

#### Rollout Steps
1) Land `CompletionCheck` and integrations.
2) Add settings toggles and defaults.
3) Validate on iOS 17/18 and macOS builds; guard APIs with availability.
4) Usability pass; tune durations and damping as needed.


