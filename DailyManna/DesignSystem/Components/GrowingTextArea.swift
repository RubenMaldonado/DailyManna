import SwiftUI

/// A robust, fully-interactive auto-growing text area implemented with
/// platform-native text views so the entire surface is editable and grows
/// smoothly as the user types.
struct GrowingTextArea: View {
    @Binding var text: String
    var placeholder: String
    var minLines: Int = 1
    var maxLines: Int = 6

    @State private var height: CGFloat = 0

    private var lineHeight: CGFloat { 22 } // approximate body line height
    private var minHeight: CGFloat { CGFloat(min(max(minLines, 1), maxLines)) * lineHeight + 14 }
    private var maxHeight: CGFloat { CGFloat(max(maxLines, minLines)) * lineHeight + 14 }

    var body: some View {
        VStack(spacing: 0) {
            #if os(iOS)
            GrowingTextView_iOS(text: $text, placeholder: placeholder, calculatedHeight: $height, minHeight: minHeight, maxHeight: maxHeight)
                .frame(height: max(minHeight, min(height, maxHeight)))
            #else
            GrowingTextView_macOS(text: $text, placeholder: placeholder, calculatedHeight: $height, minHeight: minHeight, maxHeight: maxHeight)
                .frame(height: max(minHeight, min(height, maxHeight)))
            #endif
        }
        .onAppear { if height == 0 { height = minHeight } }
    }
}

#if os(iOS)
import UIKit

private struct GrowingTextView_iOS: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var calculatedHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView()
        tv.backgroundColor = .clear
        tv.font = UIFont.preferredFont(forTextStyle: .body)
        tv.textColor = .label
        tv.textContainerInset = UIEdgeInsets(top: 8, left: 6, bottom: 8, right: 6)
        tv.isScrollEnabled = false
        tv.delegate = context.coordinator
        tv.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        tv.text = text

        // Placeholder
        let placeholderLabel = UILabel()
        placeholderLabel.text = placeholder
        placeholderLabel.textColor = UIColor.secondaryLabel
        placeholderLabel.font = tv.font
        placeholderLabel.numberOfLines = 0
        placeholderLabel.translatesAutoresizingMaskIntoConstraints = false
        placeholderLabel.isUserInteractionEnabled = false
        tv.addSubview(placeholderLabel)
        NSLayoutConstraint.activate([
            placeholderLabel.leadingAnchor.constraint(equalTo: tv.leadingAnchor, constant: 10),
            placeholderLabel.trailingAnchor.constraint(lessThanOrEqualTo: tv.trailingAnchor, constant: -8),
            placeholderLabel.topAnchor.constraint(equalTo: tv.topAnchor, constant: 8)
        ])
        context.coordinator.placeholderLabel = placeholderLabel
        placeholderLabel.isHidden = !text.isEmpty

        DispatchQueue.main.async { context.coordinator.recalculateHeight(view: tv) }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        if uiView.text != text {
            uiView.text = text
        }
        context.coordinator.placeholderLabel?.isHidden = !text.isEmpty
        context.coordinator.recalculateHeight(view: uiView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: GrowingTextView_iOS
        weak var placeholderLabel: UILabel?

        init(parent: GrowingTextView_iOS) { self.parent = parent }

        func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
            placeholderLabel?.isHidden = !textView.text.isEmpty
            recalculateHeight(view: textView)
        }

        func recalculateHeight(view: UITextView) {
            let targetSize = CGSize(width: view.bounds.width, height: .greatestFiniteMagnitude)
            let size = view.sizeThatFits(targetSize)
            let clamped = max(parent.minHeight, min(size.height, parent.maxHeight))
            if abs(parent.calculatedHeight - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.calculatedHeight = clamped }
            }
            view.isScrollEnabled = size.height > parent.maxHeight
        }
    }
}
#else
import AppKit

private struct GrowingTextView_macOS: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var calculatedHeight: CGFloat
    var minHeight: CGFloat
    var maxHeight: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.drawsBackground = false
        textView.font = NSFont.preferredFont(forTextStyle: .body)
        textView.textColor = .labelColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = context.coordinator
        textView.string = text

        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.hasVerticalScroller = false
        scroll.documentView = textView
        scroll.contentView.postsBoundsChangedNotifications = true

        // Placeholder as subview of the textView to avoid intercepting clicks
        let placeholderField = NSTextField(labelWithString: placeholder)
        placeholderField.textColor = .secondaryLabelColor
        placeholderField.font = textView.font
        placeholderField.isHidden = !text.isEmpty
        placeholderField.isSelectable = false
        placeholderField.translatesAutoresizingMaskIntoConstraints = false
        placeholderField.backgroundColor = .clear
        placeholderField.isBezeled = false
        textView.addSubview(placeholderField)
        NSLayoutConstraint.activate([
            placeholderField.leadingAnchor.constraint(equalTo: textView.leadingAnchor, constant: 10),
            placeholderField.trailingAnchor.constraint(lessThanOrEqualTo: textView.trailingAnchor, constant: -8),
            placeholderField.topAnchor.constraint(equalTo: textView.topAnchor, constant: 8)
        ])
        context.coordinator.placeholderField = placeholderField

        DispatchQueue.main.async { context.coordinator.recalculateHeight(textView: textView) }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text { textView.string = text }
        context.coordinator.placeholderField?.isHidden = !text.isEmpty
        context.coordinator.recalculateHeight(textView: textView)
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: GrowingTextView_macOS
        weak var placeholderField: NSTextField?

        init(parent: GrowingTextView_macOS) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            parent.text = tv.string
            placeholderField?.isHidden = !tv.string.isEmpty
            recalculateHeight(textView: tv)
        }

        func recalculateHeight(textView: NSTextView) {
            guard let container = textView.textContainer, let layout = textView.layoutManager else { return }
            layout.ensureLayout(for: container)
            let used = layout.usedRect(for: container)
            let contentHeight = used.height + textView.textContainerInset.height * 2
            let clamped = max(parent.minHeight, min(contentHeight, parent.maxHeight))
            if abs(parent.calculatedHeight - clamped) > 0.5 {
                DispatchQueue.main.async { self.parent.calculatedHeight = clamped }
            }
            let shouldScroll = contentHeight > parent.maxHeight
            (textView.enclosingScrollView)?.hasVerticalScroller = shouldScroll
        }
    }
}
#endif


