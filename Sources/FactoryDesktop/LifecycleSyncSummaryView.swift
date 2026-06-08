import FactoryDesktopCore
import SwiftUI

struct LifecycleSyncSummaryView: View {
    var result: TaskLifecycleSyncResult?
    var emptyMessage: String

    var body: some View {
        if let result {
            let details = TaskLifecycleSyncDetails.make(from: result)
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        LifecycleSummaryChip(label: "Action", value: result.evaluation.recommendedAction.displayName)
                        LifecycleSummaryChip(label: "Status", value: result.evaluation.recommendedStatus.displayName)
                        LifecycleSummaryChip(
                            label: "Auto",
                            value: result.evaluation.isAutomaticSafe ? "safe" : "manual",
                            tone: result.evaluation.isAutomaticSafe ? .ok : .warning
                        )
                    }

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(details.rows) { row in
                            LifecycleSummaryChip(label: row.label, value: row.value, tone: row.tone)
                        }
                    }

                    if let transition = details.transition {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Automatic Transition")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text("\(transition.fromStatus.displayName) -> \(transition.toStatus.displayName)")
                                .font(.subheadline.weight(.semibold))
                            Text(transition.reason)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } else if !details.blockingReasons.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Sync Did Not Apply")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            ForEach(details.blockingReasons, id: \.self) { reason in
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        Text(details.evaluationReason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)
            } label: {
                HStack(spacing: 8) {
                    Label("Lifecycle Facts", systemImage: result.evaluation.isAutomaticSafe ? "checkmark.shield" : "exclamationmark.triangle")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Text(result.didApply ? "Applied" : (result.evaluation.isAutomaticSafe ? "Safe" : "Manual review"))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(result.evaluation.isAutomaticSafe ? .green : .orange)
                }
            }
        } else {
            Text(emptyMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct LifecycleSummaryChip: View {
    var label: String
    var value: String
    var tone: TaskLifecycleFactTone = .neutral

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(tone.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(tone.color.opacity(0.28))
        )
    }
}

private extension TaskLifecycleFactTone {
    var color: Color {
        switch self {
        case .neutral:
            return .secondary
        case .ok:
            return .green
        case .warning:
            return .orange
        case .danger:
            return .red
        }
    }
}
