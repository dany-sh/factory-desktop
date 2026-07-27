import AppKit
import FactoryDesktopCore
import SwiftUI
import UniformTypeIdentifiers

struct ConveyorBoardView: View {
    @ObservedObject var store: ConveyorBoardStore
    @State private var pendingExecution: PendingExecution?
    @SceneStorage("conveyor.board.sidebar-visible") private var sidebarVisible = true
    @SceneStorage("conveyor.board.inspector-visible") private var inspectorVisible = false
    @SceneStorage("conveyor.board.show-done") private var showDone = false

    var body: some View {
        HSplitView {
            NavigationSplitView(columnVisibility: sidebarVisibilityBinding) {
                ConveyorProjectSidebar(store: store)
                    .navigationSplitViewColumnWidth(min: 180, ideal: 240, max: 300)
            } detail: {
                board
                    .navigationSplitViewColumnWidth(min: 420, ideal: 820)
            }

            if store.isInspectorVisible, store.selectedFeature != nil {
                ConveyorFeatureInspector(store: store)
                    .frame(minWidth: 260, idealWidth: 320, maxWidth: 420, maxHeight: .infinity)
            }
        }
        .navigationTitle(store.selectedProject.name)
        .searchable(text: $store.searchText, prompt: "Search features")
        .toolbar { toolbar }
        .task { await store.refresh() }
        .onAppear {
            if store.selectedFeatureID == nil { inspectorVisible = false }
            store.isSidebarVisible = sidebarVisible
            store.isInspectorVisible = inspectorVisible
        }
        .onChange(of: sidebarVisible) { _, visible in store.isSidebarVisible = visible }
        .onChange(of: inspectorVisible) { _, visible in store.isInspectorVisible = visible }
        .onChange(of: store.isSidebarVisible) { _, visible in sidebarVisible = visible }
        .onChange(of: store.isInspectorVisible) { _, visible in inspectorVisible = visible }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await store.refresh() }
        }
        .alert(item: $pendingExecution) { execution in
            Alert(
                title: Text(execution.title),
                message: Text(execution.message),
                primaryButton: .default(Text(execution.confirmation)) {
                    Task {
                        switch execution.kind {
                        case let .thisFeature(feature): await store.runThis(feature)
                        case .next: await store.runNext()
                        }
                    }
                },
                secondaryButton: .cancel()
            )
        }
        .alert("Conveyor", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    private var sidebarVisibilityBinding: Binding<NavigationSplitViewVisibility> {
        Binding(
            get: { sidebarVisible ? .all : .detailOnly },
            set: { sidebarVisible = $0 != .detailOnly }
        )
    }

    private var scopeBinding: Binding<ConveyorScope> {
        Binding(
            get: { store.scope },
            set: { scope in Task { await store.setScope(scope) } }
        )
    }

    private var milestoneBinding: Binding<String?> {
        Binding(
            get: { store.milestoneFilter },
            set: { milestone in Task { await store.setMilestoneFilter(milestone) } }
        )
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if !sidebarVisible {
                Menu {
                    ForEach(store.projects) { project in
                        Button(project.name) { Task { await store.selectProject(project.id) } }
                    }
                } label: {
                    Label(store.selectedProject.name, systemImage: "folder")
                }
            }
        }

        ToolbarItem(placement: .navigation) {
            Menu {
                Section("Browse") {
                    Picker("Scope", selection: scopeBinding) {
                        ForEach(ConveyorScope.allCases) { scope in
                            Text(scope.title).tag(scope)
                        }
                    }

                    if store.scope != .active, let queue = store.queue {
                        Picker("Milestone", selection: milestoneBinding) {
                            Text("All Milestones").tag(String?.none)
                            ForEach(queue.milestones) { milestone in
                                Text(milestone.active ? "\(milestone.milestoneID) (Active)" : milestone.milestoneID)
                                    .tag(String?.some(milestone.milestoneID))
                            }
                        }
                    }
                }

                Section("Filter") {
                    Picker("Priority", selection: $store.priorityFilter) {
                        Text("All priorities").tag(ConveyorPriority?.none)
                        ForEach(ConveyorPriority.allCases) { priority in
                            Text(priority.rawValue).tag(ConveyorPriority?.some(priority))
                        }
                    }
                    Picker("Status", selection: $store.statusFilter) {
                        Text("All statuses").tag(ConveyorColumn?.none)
                        ForEach(ConveyorColumn.allCases) { column in
                            Text(column.rawValue).tag(ConveyorColumn?.some(column))
                        }
                    }
                }

                if store.hasActiveFilters {
                    Divider()
                    Button("Reset Filters") { store.resetFilters() }
                }
            } label: {
                Label("Filters", systemImage: "line.3.horizontal.decrease.circle")
            }
            .help("Choose the board scope and filters")
        }

        ToolbarItemGroup(placement: .primaryAction) {

            Button {
                pendingExecution = PendingExecution(kind: .next)
            } label: {
                Label("Run Next", systemImage: "play.fill")
            }
            .disabled(store.queue?.nextReadyFeature == nil || store.mutationInFlight)
            .keyboardShortcut("r", modifiers: [.command, .option])

            Button {
                Task { await store.setPaused(!(store.queue?.paused ?? false)) }
            } label: {
                Label(store.queue?.paused == true ? "Unpause" : "Pause After Current", systemImage: store.queue?.paused == true ? "playpause" : "pause.fill")
            }
            .disabled(store.queue == nil || store.mutationInFlight)
            .keyboardShortcut("p", modifiers: [.command, .option])
        }

        ToolbarItem(placement: .navigation) {
            Button {
                store.toggleInspector()
            } label: {
                Label("Toggle Inspector", systemImage: "sidebar.trailing")
            }
            .help("Show or hide the feature inspector")
            .disabled(store.selectedFeature == nil)
        }

        ToolbarItem(placement: .secondaryAction) {
            Menu {
                if let queue = store.queue, queue.terminalFeatureCount > 0 {
                    Toggle("Show Done", isOn: $showDone)
                }
                Divider()
                Button("Refresh") { Task { await store.refresh() } }
                    .disabled(store.isLoading || store.mutationInFlight)
                    .keyboardShortcut("r", modifiers: .command)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
    }

    private var board: some View {
        Group {
            if let queue = store.queue {
                VStack(alignment: .leading, spacing: 0) {
                    boardSummary(queue)
                    ConveyorPriorityDropStrip(store: store)
                    GeometryReader { geometry in
                        let columns = displayedColumns
                        let columnSpacing: CGFloat = 14
                        let horizontalInsets: CGFloat = 36
                        let columnOuterPadding: CGFloat = 16
                        let availableWidth = geometry.size.width - horizontalInsets - columnSpacing * CGFloat(max(columns.count - 1, 0))
                        let columnWidth = max(180, availableWidth / CGFloat(max(columns.count, 1)) - columnOuterPadding)

                        ScrollView(.horizontal) {
                            HStack(alignment: .top, spacing: columnSpacing) {
                                ForEach(columns) { column in
                                    ConveyorKanbanColumn(
                                        column: column,
                                        features: store.features(in: column),
                                        emptyMessage: emptyMessage(for: column, queue: queue),
                                        showsMilestone: store.scope != .active,
                                        width: columnWidth,
                                        store: store
                                    )
                                }
                            }
                            .padding(18)
                        }
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if store.isLoading {
                        ProgressView().controlSize(.small).padding(16)
                    }
                }
                .accessibilityLabel("\(queue.projectID) Kanban board")
            } else if store.isLoading {
                ProgressView("Loading Conveyor queue…")
            } else {
                ContentUnavailableView(
                    "No Queue Loaded",
                    systemImage: "rectangle.3.group",
                    description: Text("Refresh to load the controller’s read-only queue projection."))
            }
        }
    }

    private var displayedColumns: [ConveyorColumn] {
        ConveyorColumn.allCases.filter { column in
            guard column == .done else { return true }
            return showDone && store.features(in: .done).isEmpty == false
        }
    }

    private func boardSummary(_ queue: ConveyorQueue) -> some View {
        let hiddenDoneCount = store.features(in: .done).count
        let displayedFeatureCount = displayedColumns.flatMap { store.features(in: $0) }.count
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("\(displayedFeatureCount) shown of \(queue.features.count) features")
                    .font(.headline)
                if hiddenDoneCount > 0, !showDone {
                    Button("\(hiddenDoneCount) completed hidden") { showDone = true }
                        .buttonStyle(.link)
                        .font(.caption)
                }
                Spacer()
            }
            Text("Current milestone: \(queue.activeMilestone)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    private func emptyMessage(for column: ConveyorColumn, queue: ConveyorQueue) -> String {
        if store.hasActiveFilters { return "No features match the current filters." }
        if queue.scope == .unfinished, queue.visibleNonterminalCount == 0 {
            return "No unfinished features exist across known milestones."
        }
        if queue.scope == .active {
            return "No \(column.rawValue) features in \(queue.activeMilestone)"
        }
        return "No \(column.rawValue) features"
    }
}

private struct ConveyorPriorityDropStrip: View {
    @ObservedObject var store: ConveyorBoardStore

    var body: some View {
        HStack(spacing: 8) {
            Text("Priority")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(ConveyorPriority.allCases) { priority in
                Text(priority.rawValue)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.quaternary, in: Capsule())
                    .onDrop(of: [UTType.text], delegate: ConveyorPriorityDropDelegate(priority: priority, store: store))
                    .accessibilityLabel("Set priority \(priority.rawValue) by dropping a Backlog or Ready card")
            }
            Spacer()
            Text("Drop a Backlog or Ready card to change priority")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.bar)
    }
}

private struct ConveyorProjectSidebar: View {
    @ObservedObject var store: ConveyorBoardStore

    var body: some View {
        List {
            Section("Projects") {
                ForEach(store.projects) { project in
                    Button {
                        Task { await store.selectProject(project.id) }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: project.id == store.selectedProjectID ? "square.grid.2x2.fill" : "square.grid.2x2")
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.name).lineLimit(1)
                                if let queue = store.queues[project.id] {
                                    Text(summary(for: queue))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(project.id == store.selectedProjectID ? Color.accentColor.opacity(0.14) : nil)
                }
            }

            if let queue = store.queue {
                Section("Current Project") {
                    Label(queue.paused ? "Paused" : (queue.activeFeature == nil ? "Idle" : "Running"), systemImage: queue.paused ? "pause.circle" : (queue.activeFeature == nil ? "circle" : "play.circle.fill"))
                    Label("\(store.features(in: .ready).count) Ready", systemImage: "checkmark.circle")
                    Label("\(store.features(in: .blocked).count) Blocked", systemImage: "exclamationmark.triangle")
                    Label(queue.activeMilestone, systemImage: "flag")
                }
            }
        }
        .listStyle(.sidebar)
    }

    private func summary(for queue: ConveyorQueue) -> String {
        if queue.paused { return "Paused" }
        if queue.activeFeature != nil { return "Running" }
        let blocked = queue.features.filter { $0.kanbanColumn == .blocked }.count
        return blocked > 0 ? "\(blocked) blocked" : "Ready"
    }
}

private struct ConveyorKanbanColumn: View {
    let column: ConveyorColumn
    let features: [ConveyorFeature]
    let emptyMessage: String
    let showsMilestone: Bool
    let width: CGFloat
    @ObservedObject var store: ConveyorBoardStore

    var body: some View {
        ConveyorAdaptiveSurface {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text(column.rawValue).font(.headline)
                    Spacer()
                    Text("\(features.count)").foregroundStyle(.secondary).font(.caption.weight(.semibold))
                }
                ScrollView {
                    LazyVStack(spacing: 8) {
                        if features.isEmpty {
                            Text(emptyMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, minHeight: 74)
                        }
                        ForEach(features) { feature in
                            ConveyorFeatureCard(
                                feature: feature,
                                selected: store.selectedFeatureID == feature.id,
                                showsMilestone: showsMilestone,
                                select: { store.selectFeature(feature.id) },
                                inspect: { store.inspect(feature.id) }
                            )
                            .onDrop(of: [UTType.text], delegate: ConveyorDropDelegate(
                                target: feature,
                                column: column,
                                store: store
                            ))
                        }
                    }
                }
            }
        }
        .frame(width: width, alignment: .top)
        .frame(minHeight: 500, idealHeight: 620, maxHeight: .infinity, alignment: .top)
        .padding(8)
        .onDrop(of: [ConveyorFeatureDrag.contentType], delegate: ConveyorColumnDropDelegate(column: column, store: store))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(column.rawValue) column")
    }
}

private struct ConveyorAdaptiveSurface<Content: View>: View {
    @ViewBuilder let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }
}

private struct ConveyorFeatureCard: View {
    let feature: ConveyorFeature
    let selected: Bool
    let showsMilestone: Bool
    let select: () -> Void
    let inspect: () -> Void

    var body: some View {
        Button(action: select) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(feature.featureID).font(.caption.monospaced())
                    Spacer()
                    Text(feature.priority.rawValue)
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 6).padding(.vertical, 3)
                        .background(priorityColor.opacity(0.16), in: Capsule())
                }
                Text(feature.title).font(.subheadline.weight(.semibold)).lineLimit(2)
                if showsMilestone {
                    Text("\(feature.milestone) · \(feature.priority.rawValue) · \(feature.kanbanColumn.rawValue)")
                        .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Text(feature.blockedReason ?? feature.status.replacingOccurrences(of: "_", with: " "))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if let model = feature.executionModel, let reasoning = feature.reasoning {
                    Text("\(shortModel(model)) · \(reasoning)")
                        .font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(selected ? Color.accentColor.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous).stroke(selected ? Color.accentColor.opacity(0.65) : Color.secondary.opacity(0.2)))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onDrag { ConveyorFeatureDrag.provider(for: feature.featureID) }
        .simultaneousGesture(TapGesture().onEnded(select))
        .simultaneousGesture(TapGesture(count: 2).onEnded(inspect))
        .accessibilityHint("Double-click to open the feature inspector")
        .contextMenu {
            Button("Open Inspector") { inspect() }
        }
    }

    private var priorityColor: Color {
        switch feature.priority {
        case .p1: .red
        case .p2: .orange
        case .p3: .secondary
        }
    }

    private func shortModel(_ value: String) -> String {
        value.replacingOccurrences(of: "gpt-5.6-", with: "")
    }
}

private struct ConveyorDropDelegate: DropDelegate {
    let target: ConveyorFeature
    let column: ConveyorColumn
    @ObservedObject var store: ConveyorBoardStore

    func validateDrop(info: DropInfo) -> Bool {
        (column == .backlog || column == .ready) && info.hasItemsConforming(to: [ConveyorFeatureDrag.contentType])
    }

    func performDrop(info: DropInfo) -> Bool {
        ConveyorFeatureDrag.loadFeatureID(from: info) { featureID in
            Task { @MainActor in
                guard let feature = store.queue?.features.first(where: { $0.featureID == featureID }) else { return }
                await store.drop(feature, onto: target, column: column)
            }
        }
    }
}

private struct ConveyorColumnDropDelegate: DropDelegate {
    let column: ConveyorColumn
    @ObservedObject var store: ConveyorBoardStore

    func validateDrop(info: DropInfo) -> Bool {
        (column == .backlog || column == .ready) && info.hasItemsConforming(to: [ConveyorFeatureDrag.contentType])
    }

    func performDrop(info: DropInfo) -> Bool {
        ConveyorFeatureDrag.loadFeatureID(from: info) { featureID in
            Task { @MainActor in
                guard let feature = store.queue?.features.first(where: { $0.featureID == featureID }) else { return }
                await store.drop(feature, onto: nil, column: column)
            }
        }
    }
}

private struct ConveyorPriorityDropDelegate: DropDelegate {
    let priority: ConveyorPriority
    @ObservedObject var store: ConveyorBoardStore

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [ConveyorFeatureDrag.contentType])
    }

    func performDrop(info: DropInfo) -> Bool {
        ConveyorFeatureDrag.loadFeatureID(from: info) { featureID in
            Task { @MainActor in
                guard let feature = store.queue?.features.first(where: { $0.featureID == featureID }),
                      store.actionReason(.setPriority, for: feature) == nil else { return }
                await store.setPriority(feature, priority: priority)
            }
        }
    }
}

private enum ConveyorFeatureDrag {
    static let contentType = UTType.utf8PlainText

    static func provider(for featureID: String) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: contentType.identifier, visibility: .all) { completion in
            completion(Data(featureID.utf8), nil)
            return nil
        }
        return provider
    }

    static func loadFeatureID(from info: DropInfo, receive: @escaping (String) -> Void) -> Bool {
        guard let provider = info.itemProviders(for: [contentType]).first else { return false }
        provider.loadDataRepresentation(forTypeIdentifier: contentType.identifier) { data, _ in
            guard let data,
                  let featureID = String(data: data, encoding: .utf8),
                  !featureID.isEmpty else { return }
            receive(featureID)
        }
        return true
    }
}

private struct ConveyorFeatureInspector: View {
    @ObservedObject var store: ConveyorBoardStore
    @State private var pendingRun = false

    var body: some View {
        Group {
            if let feature = store.selectedFeature {
                Form {
                    Section(feature.featureID) {
                        Text(feature.title).font(.headline)
                        if !feature.description.isEmpty { Text(feature.description).foregroundStyle(.secondary) }
                    }
                    Section("Queue") {
                        LabeledContent("Status", value: feature.status)
                        LabeledContent("Position", value: "\(feature.queuePosition)")
                        Picker("Priority", selection: Binding(
                            get: { feature.priority },
                            set: { priority in Task { await store.setPriority(feature, priority: priority) } }
                        )) {
                            ForEach(ConveyorPriority.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .disabled(store.actionReason(.setPriority, for: feature) != nil || store.mutationInFlight)
                        if let reason = store.actionReason(.setPriority, for: feature) { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    }
                    Section("Dependencies") {
                        Text(feature.dependencies.isEmpty ? "No dependencies" : feature.dependencies.joined(separator: ", "))
                        Label(feature.dependenciesComplete ? "Complete" : "Incomplete", systemImage: feature.dependenciesComplete ? "checkmark.circle" : "exclamationmark.triangle")
                        if let blocker = feature.blockedReason { Text(blocker).foregroundStyle(.secondary) }
                    }
                    Section("Execution") {
                        LabeledContent("Profile", value: feature.executionProfile.profile ?? "Not resolved")
                        LabeledContent("Model", value: feature.executionModel ?? "Not resolved")
                        LabeledContent("Reasoning", value: feature.reasoning ?? "Not resolved")
                        if let branch = feature.branch { LabeledContent("Branch", value: branch) }
                        if let commit = feature.commit { LabeledContent("Commit", value: commit) }
                        if let result = feature.latestTerminalResult { LabeledContent("Latest result", value: result.summary) }
                    }
                    Section {
                        if let specificationPath = feature.specificationPath {
                            Button("Open Specification") { NSWorkspace.shared.open(URL(fileURLWithPath: specificationPath)) }
                        }
                        Button("Mark Ready") { Task { await store.markReady(feature) } }
                            .disabled(store.actionReason(.markReady, for: feature) != nil || store.mutationInFlight)
                        if let reason = store.actionReason(.markReady, for: feature) { Text(reason).font(.caption).foregroundStyle(.secondary) }
                        Button("Move to Backlog") { Task { await store.moveToBacklog(feature) } }
                            .disabled(store.actionReason(.moveToBacklog, for: feature) != nil || store.mutationInFlight)
                        if let reason = store.actionReason(.moveToBacklog, for: feature) { Text(reason).font(.caption).foregroundStyle(.secondary) }
                        Button("Run This Feature") { pendingRun = true }
                            .disabled(store.actionReason(.runThis, for: feature) != nil || store.mutationInFlight)
                            .keyboardShortcut(.return, modifiers: [.command])
                        if let reason = store.actionReason(.runThis, for: feature) { Text(reason).font(.caption).foregroundStyle(.secondary) }
                    }
                }
                .formStyle(.grouped)
                .alert("Run \(feature.featureID)?", isPresented: $pendingRun) {
                    Button("Run Feature") { Task { await store.runThis(feature) } }
                    Button("Cancel", role: .cancel) {}
                } message: { Text("This starts the selected Conveyor feature transaction. Dragging cards never starts work.") }
            } else {
                ContentUnavailableView("No Feature Selected", systemImage: "sidebar.right", description: Text("Select a card to inspect its controller evidence and legal actions."))
            }
        }
    }
}

private struct PendingExecution: Identifiable {
    enum Kind { case thisFeature(ConveyorFeature), next }
    let kind: Kind
    var id: String { title }
    var title: String { if case let .thisFeature(feature) = kind { return "Run \(feature.featureID)?" }; return "Run Next Feature?" }
    var message: String { if case .thisFeature = kind { return "This starts the selected Conveyor feature transaction." }; return "This starts at most one deterministic feature cycle and stops at its terminal boundary." }
    var confirmation: String { if case .thisFeature = kind { return "Run Feature" }; return "Run Next" }
}
