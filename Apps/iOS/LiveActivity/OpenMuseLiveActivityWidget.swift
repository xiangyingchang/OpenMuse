import ActivityKit
import OpenMuseCore
import SwiftUI
import WidgetKit

@main
struct OpenMuseLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: OpenMuseTaskActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.blue)
                    .frame(width: 38, height: 38)
                    .background(Color.blue.opacity(0.14), in: Circle())
                VStack(alignment: .leading, spacing: 4) {
                    Text("OpenMuse")
                        .font(.headline)
                    Text(statusTitle(for: context))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 8)
                if !isFinished(context.state.phase) {
                    ProgressView()
                        .tint(Color.blue)
                        .accessibilityLabel("任务进行中")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .activityBackgroundTint(Color.black)
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Color.blue)
                        .padding(.top, 2)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OpenMuse")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(statusTitle(for: context))
                            .font(.subheadline.weight(.medium))
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if isFinished(context.state.phase) {
                        Image(systemName: context.state.phase == .completed ? "checkmark.circle.fill" : "xmark.circle.fill")
                            .foregroundStyle(context.state.phase == .completed ? Color.green : Color.orange)
                    } else {
                        ProgressView()
                            .tint(Color.blue)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(context.isStale ? "进度暂时没有更新，打开 OpenMuse 查看" : "完成后会自动收起")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.blue)
            } compactTrailing: {
                Text(context.state.phase.compactTitle)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            } minimal: {
                Image(systemName: "sparkles")
                    .foregroundStyle(Color.blue)
            }
            .keylineTint(Color.blue)
        }
    }

    private func statusTitle(for context: ActivityViewContext<OpenMuseTaskActivityAttributes>) -> String {
        context.isStale ? "进度暂时没有更新" : context.state.phase.title
    }

    private func isFinished(_ phase: OpenMuseLiveActivityPhase) -> Bool {
        [.completed, .failed, .stopped].contains(phase)
    }
}
