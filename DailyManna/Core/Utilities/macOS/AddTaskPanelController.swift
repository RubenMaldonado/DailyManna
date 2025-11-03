import AppKit
import SwiftUI

#if os(macOS)

@MainActor
final class AddTaskPanelController: NSObject, NSWindowDelegate {
    private var panel: NSPanel?
    private var hostingController: NSHostingController<AddTaskPanelView>?
    private var currentDraftId: UUID?
    private var pendingLabelSelections: [UUID: Set<UUID>] = [:]
    private var pendingRecurrenceSelections: [UUID: RecurrenceRule] = [:]
    private var observers: [NSObjectProtocol] = []

    override init() {
        super.init()
        installObservers()
    }

    deinit {
        MainActor.assumeIsolated {
        removeObservers()
        panel?.delegate = nil
        }
    }

    func show(authService: AuthenticationService) {
        guard case let .authenticated(user) = authService.authState else {
            Logger.shared.info("Global add-task shortcut ignored: no authenticated user", category: .ui)
            return
        }

        let draft = makeDraft(for: user.id)
        currentDraftId = draft.id
        pendingLabelSelections.removeAll()
        pendingRecurrenceSelections.removeAll()

        let root = AddTaskPanelView(
            draft: draft,
            authService: authService,
            onSubmit: { [weak self] draft in
                self?.handleSubmit(draft: draft, userId: user.id)
            },
            onCancel: { [weak self] in
                self?.dismiss()
            }
        )

        if hostingController == nil {
            hostingController = NSHostingController(rootView: root)
        } else {
            hostingController?.rootView = root
        }

        let panel = panel ?? makePanel()
        panel.delegate = self
        panel.contentViewController = hostingController

        positionPanelIfNeeded(panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.orderFrontRegardless()
        self.panel = panel
    }

    func dismiss() {
        guard let panel else { return }
        panel.close()
    }

    func windowWillClose(_ notification: Notification) {
        cleanupState()
    }

    // MARK: - Private helpers

    private func installObservers() {
        let center = NotificationCenter.default
        let labels = center.addObserver(forName: Notification.Name("dm.taskform.labels.selection"), object: nil, queue: .main) { [weak self] note in
            guard let taskId = note.userInfo?["taskId"] as? UUID,
                  let ids = note.userInfo?["labelIds"] as? [UUID] else { return }
            _Concurrency.Task { @MainActor [weak self] in
                guard let self, taskId == self.currentDraftId else { return }
            self.pendingLabelSelections[taskId] = Set(ids)
            }
        }
        observers.append(labels)

        let recurrence = center.addObserver(forName: Notification.Name("dm.taskform.recurrence.selection"), object: nil, queue: .main) { [weak self] note in
            guard let taskId = note.userInfo?["taskId"] as? UUID,
                  let data = note.userInfo?["ruleJSON"] as? Data,
                  let rule = try? JSONDecoder().decode(RecurrenceRule.self, from: data) else { return }
            _Concurrency.Task { @MainActor [weak self] in
                guard let self, taskId == self.currentDraftId else { return }
            self.pendingRecurrenceSelections[taskId] = rule
            }
        }
        observers.append(recurrence)

        let recurrenceClear = center.addObserver(forName: Notification.Name("dm.taskform.recurrence.clear"), object: nil, queue: .main) { [weak self] note in
            guard let taskId = note.userInfo?["taskId"] as? UUID else { return }
            _Concurrency.Task { @MainActor [weak self] in
                guard let self, taskId == self.currentDraftId else { return }
            self.pendingRecurrenceSelections.removeValue(forKey: taskId)
            }
        }
        observers.append(recurrenceClear)
    }

    private func removeObservers() {
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        observers.removeAll()
    }

    private func makeDraft(for userId: UUID) -> TaskDraft {
        TaskDraft(userId: userId, bucket: .thisWeek)
    }

    private func makePanel() -> NSPanel {
        let frame = NSRect(x: 0, y: 0, width: 520, height: 420)
        let style: NSWindow.StyleMask = [.titled, .closable, .utilityWindow]
        let panel = FloatingAddTaskPanel(contentRect: frame, styleMask: style, backing: .buffered, defer: false)
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.title = "Add Task"
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.isMovableByWindowBackground = true
        panel.delegate = self
        panel.setContentSize(NSSize(width: 520, height: 420))
        panel.minSize = NSSize(width: 520, height: 420)
        return panel
    }

    private func positionPanelIfNeeded(_ panel: NSPanel) {
        guard let screen = NSScreen.main else { return }
        if panel.frame.origin == .zero {
            let frame = panel.frameRect(forContentRect: NSRect(x: 0, y: 0, width: 520, height: 420))
            let x = screen.frame.midX - frame.width / 2
            let y = screen.frame.midY - frame.height / 2
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func cleanupState() {
        currentDraftId = nil
        pendingLabelSelections.removeAll()
        pendingRecurrenceSelections.removeAll()
        panel?.contentViewController = nil
        hostingController = nil
    }

    private func handleSubmit(draft: TaskDraft, userId: UUID) {
        _Concurrency.Task { [weak self] in
            guard let self else { return }
            do {
                let deps = Dependencies.shared
                let taskUseCases: TaskUseCases = try deps.resolve(type: TaskUseCases.self)
                let recurrenceUseCases: RecurrenceUseCases? = try? deps.resolve(type: RecurrenceUseCases.self)

                let newTask = draft.toNewTask()
                try await taskUseCases.createTask(newTask)
                NotificationCenter.default.post(name: Notification.Name("dm.task.created"), object: nil, userInfo: ["taskId": newTask.id])

                if let due = newTask.dueAt {
                    let scheduleAt: Date = {
                        if newTask.dueHasTime { return due }
                        var comps = Calendar.current.dateComponents([.year, .month, .day], from: due)
                        comps.hour = 12
                        comps.minute = 0
                        return Calendar.current.date(from: comps) ?? due
                    }()
                    await NotificationsManager.scheduleDueNotification(taskId: newTask.id, title: newTask.title, dueAt: scheduleAt, bucketKey: newTask.bucketKey.rawValue)
                }

                if let desired = self.pendingLabelSelections.removeValue(forKey: draft.id) {
                    try await taskUseCases.setLabels(for: newTask.id, to: desired, userId: userId)
                }

                if let rule = self.pendingRecurrenceSelections.removeValue(forKey: draft.id), let recUC = recurrenceUseCases {
                    let recurrence = Recurrence(userId: userId, taskTemplateId: newTask.id, rule: rule)
                    try await recUC.create(recurrence)
                }

                await MainActor.run {
                    self.dismiss()
                }
            } catch {
                Logger.shared.error("Failed to create task from global shortcut", category: .ui, error: error)
            }
        }
    }
}

// MARK: - Root SwiftUI wrapper to intercept dismiss calls

private struct AddTaskPanelRoot: View {
    let draft: TaskDraft
    let onSubmit: (TaskDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        TaskComposerView(draft: draft, onSubmit: onSubmit, onCancel: onCancel)
    }
}

private struct AddTaskPanelView: View {
    let draft: TaskDraft
    let authService: AuthenticationService
    let onSubmit: (TaskDraft) -> Void
    let onCancel: () -> Void

    var body: some View {
        AddTaskPanelRoot(draft: draft, onSubmit: onSubmit, onCancel: onCancel)
            .environmentObject(authService)
    }
}

private final class FloatingAddTaskPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

#endif

