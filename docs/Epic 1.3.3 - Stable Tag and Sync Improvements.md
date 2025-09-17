## Epic 1.3.3 — Stable Tag and Sync Improvements

### Stable checkpoint

- Tag: `stable-20250917`
- Commit: "chore: checkpoint before sync improvements (stable)"
- Purpose: Reproducible baseline before adding realtime targeted upserts and background refresh.

### Planned work

1) Realtime → targeted upserts (tasks, then labels)
   - Replace hint-only realtime with payload-driven targeted upserts.
   - Benefits: near-instant updates, smaller bandwidth, fewer UI list jumps.

2) BGTaskScheduler (background refresh, iOS)
   - Register `com.rubentena.dailymanna.refresh` and run timeboxed delta sync.
   - Benefits: fresher data on app launch; system-managed efficiency.

3) Reachability gating (supporting both)
   - Pause sync triggers offline; catch up immediately on reconnect.

4) Paginated delta pulls (supporting both)
   - Robust bootstrap and large-delta handling without memory spikes.

### Verification

- Multi-device realtime changes (create/update/complete/delete) appear within ~1–2s.
- Background task completes within budget and re-schedules itself.
- Offline/online transitions avoid retry spam and catch up promptly.

### Rollback

- Revert to `stable-20250917` if any regression is detected.


