import AIOutputSDK
import LocalDiffService
import MarkdownUIToolkit
import PlanFeature
import PlanService
import RepositorySDK
import SwiftUI

struct PlanDetailView: View {
  @Environment(ExecutionPanelModel.self) private var panelModel
  @Environment(\.gitWorkingDirectoryMonitor) private var gitWorkingDirectoryMonitor
  @Environment(\.localDiffService) private var localDiffService
  @Environment(PlanModel.self) var planModel
  let plan: MarkdownPlanEntry
  let repository: RepositoryConfiguration

  @State private var planContent: String?
  @State private var localPhases: [PlanPhase] = []
  @State private var loadError: String?
  @State private var architectureDiagram: ArchitectureDiagram?
  @State private var selectedModule: ModuleSelection?
  @State private var isArchitectureExpanded = true
  @AppStorage("mdPlannerProviderName") private var storedProviderName = ""
  @AppStorage("planExecuteNextOnly") private var executeNextOnly = false
  @AppStorage("planStopAfterArchitectureDiagram") private var stopAfterArchitectureDiagram = false
  @AppStorage("planUseWorktree") private var useWorktree = false

  @State private var executionChatModel: ChatModel?
  @State private var activePlanModel = ActivePlanModel()
  @State private var editablePlanContent = ""
  @State private var isAddTaskPopoverPresented = false
  @State private var isAppendReviewPopoverPresented = false
  @State private var isEditingMarkdown = false
  @State private var newTaskDescription = ""

  var body: some View {
    VStack(spacing: 0) {
      headerBar

      if case .error(let error) = planModel.state {
        errorBanner(error)
      }

      planContentView
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .navigationTitle(plan.name)
    .task(id: plan.id) {
      executionChatModel = nil
      panelModel.clearOutput()
      activePlanModel.stopWatching()
      await loadPlan()
      resumeWatchingIfNeeded()
    }
    .onChange(of: planModel.phaseCompleteCount) {
      loadArchitectureDiagram()
    }
    .onChange(of: planModel.executionCompleteCount) {
      Task { await handleExecutionComplete() }
    }
    .onChange(of: activePlanModel.content) { _, newContent in
      guard !isEditingMarkdown, !newContent.isEmpty else { return }
      planContent = newContent
      editablePlanContent = newContent
      localPhases = activePlanModel.phases
    }
    .onChange(of: isEditingMarkdown) { _, isEditing in
      handleEditingModeChange(isEditing)
    }
    .onDisappear {
      activePlanModel.stopWatching()
    }
  }

  // MARK: - Sub-views

  private var planContentView: some View {
    Group {
      if shouldShowDiffSection {
        GeometryReader { geometry in
          VStack(spacing: 0) {
            planDocumentScrollView
              .frame(height: max(320, geometry.size.height * 0.5))

            Divider()

            diffSection
              .frame(height: max(320, geometry.size.height * 0.5))
          }
        }
      } else {
        planDocumentScrollView
      }
    }
  }

  private var planDocumentScrollView: some View {
    ScrollView {
      planDocumentContent
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  @ViewBuilder
  private var planDocumentContent: some View {
    VStack(alignment: .leading, spacing: 16) {
      phaseSection
      queuedTasksSection

      if let diagram = architectureDiagram {
        DisclosureGroup("Architecture", isExpanded: $isArchitectureExpanded) {
          ArchitectureDiagramView(
            diagram: diagram,
            selectedModule: $selectedModule
          )
        }
      }

      if let result = planModel.state.completionResult {
        completionBanner(result)
      }

      if let planContent {
        Divider()
        EditableMarkdownView(text: $editablePlanContent, isEditing: isEditingMarkdown)
          .frame(maxWidth: .infinity, minHeight: 320, alignment: .topLeading)
          .onAppear {
            editablePlanContent = planContent
          }
      } else if let loadError {
        ContentUnavailableView(
          "Failed to Load Plan",
          systemImage: "exclamationmark.triangle",
          description: Text(loadError)
        )
      }
    }
  }

  // MARK: - Add Task

  private var addTaskPopover: some View {
    VStack(spacing: 8) {
      Text("Add Task to Queue")
        .font(.headline)
      TextField("Task description", text: $newTaskDescription)
        .textFieldStyle(.roundedBorder)
        .frame(width: 280)
        .onSubmit {
          submitNewTask()
        }
      HStack {
        Button("Cancel") {
          newTaskDescription = ""
          isAddTaskPopoverPresented = false
        }
        .keyboardShortcut(.cancelAction)
        Spacer()
        Button("Add") {
          submitNewTask()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(newTaskDescription.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .padding()
  }

  @ViewBuilder
  private var queuedTasksSection: some View {
    let tasks = planModel.queuedTasks
    if !tasks.isEmpty {
      VStack(alignment: .leading, spacing: 6) {
        Text("Queued Tasks")
          .font(.headline)
          .foregroundStyle(.secondary)

        ForEach(tasks) { task in
          HStack(spacing: 8) {
            Image(systemName: "clock")
              .foregroundStyle(.orange)
            Text(task.description)
              .font(.body)
            Spacer()
            Button {
              planModel.removeQueuedTask(task.id)
            } label: {
              Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
  }

  private func submitNewTask() {
    let trimmed = newTaskDescription.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    planModel.queueTask(trimmed)
    newTaskDescription = ""
    isAddTaskPopoverPresented = false
  }

  // MARK: - Header

  private var isExecuting: Bool {
    if case .executing = planModel.state { return true }
    return false
  }

  private var isGenerating: Bool {
    if case .generating = planModel.state { return true }
    return false
  }

  private var isBusy: Bool { isExecuting || isGenerating }

  private var headerBar: some View {
    HStack(spacing: 12) {
      if isExecuting {
        ProgressView()
          .controlSize(.small)
        executionStatusText
      } else {
        Text(plan.relativePath(to: repository.path))
          .font(.caption)
          .foregroundStyle(.tertiary)
          .lineLimit(1)
          .truncationMode(.middle)
      }

      Spacer()

      let pipelineNodes = planModel.pipelineModel.nodes
      if isExecuting && !pipelineNodes.isEmpty {
        Text("\(pipelineNodes.filter(\.isCompleted).count)/\(pipelineNodes.count) phases")
          .foregroundStyle(.secondary)
          .font(.subheadline)
      }

      Picker("Provider", selection: Bindable(planModel).selectedProviderName) {
        ForEach(planModel.availableProviders, id: \.name) { provider in
          Text(provider.displayName).tag(provider.name)
        }
      }
      .labelsHidden()
      .frame(width: 120)
      .disabled(isBusy)
      .onChange(of: planModel.selectedProviderName) { _, newValue in
        storedProviderName = newValue
      }

      Toggle("Pause for architecture", isOn: $stopAfterArchitectureDiagram)
        .toggleStyle(.checkbox)
        .font(.caption)
        .help("Stop execution after the architecture diagram is generated")

      Toggle("Use worktree", isOn: $useWorktree)
        .toggleStyle(.checkbox)
        .font(.caption)
        .help("Run plan execution in an isolated git worktree")
        .disabled(isBusy)

            Button {
                isEditingMarkdown.toggle()
            } label: {
                Label(isEditingMarkdown ? "Done" : "Edit", systemImage: isEditingMarkdown ? "checkmark.circle" : "pencil")
            }
      .disabled(isBusy || planContent == nil)

      Button {
        completePlan()
      } label: {
        Label("Complete", systemImage: "checkmark.circle")
      }
      .disabled(isBusy)

      Button {
        isAppendReviewPopoverPresented = true
      } label: {
        Label("Append Review", systemImage: "doc.badge.plus")
      }
      .disabled(isBusy)
      .popover(isPresented: $isAppendReviewPopoverPresented) {
        AppendReviewPopover(
          plan: plan,
          reviewsDirectory: repository.path.appending(path: "docs/reviews"),
          onAppended: { Task { await loadPlan() } }
        )
      }

      Button {
        isAddTaskPopoverPresented = true
      } label: {
        Label("Add Task", systemImage: "plus.circle")
      }
      .disabled(!isExecuting)
      .popover(isPresented: $isAddTaskPopoverPresented) {
        addTaskPopover
      }

      VStack(spacing: 2) {
        HStack(spacing: 0) {
          Button(action: startExecution) {
            Image(systemName: "play.fill")
              .padding(.vertical, 5)
              .padding(.horizontal, 10)
              .contentShape(Rectangle())
          }
          .buttonStyle(.plain)

          Rectangle()
            .fill(.white.opacity(0.3))
            .frame(width: 1, height: 16)

          Menu {
            Button("Next") { executeNextOnly = true }
            Button("All") { executeNextOnly = false }
          } label: {
            Image(systemName: "chevron.down")
              .font(.caption.weight(.semibold))
              .padding(.vertical, 5)
              .padding(.horizontal, 8)
          }
          .menuIndicator(.hidden)
          .menuStyle(.borderlessButton)
          .fixedSize()
          .buttonStyle(.plain)
        }
        .foregroundStyle(.white)
        .background(isBusy ? Color(NSColor.disabledControlTextColor) : .accentColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))

        Text(executeNextOnly ? "Next" : "All")
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      .disabled(isBusy)
    }
    .padding()
  }

  @ViewBuilder
  private var executionStatusText: some View {
    let currentNode = planModel.pipelineModel.nodes.first(where: \.isCurrent)
    if let node = currentNode {
      Text(node.displayName)
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .lineLimit(1)
    } else {
      Text("Fetching status...")
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }
  }

  // MARK: - Phases

  @ViewBuilder
  private var phaseSection: some View {
    if case .running = planModel.pipelineModel.state {
      PipelineView()
        .environment(planModel.pipelineModel)
    } else if !localPhases.isEmpty {
      localPhaseList
    }
  }

  private var localPhaseList: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Phases")
        .font(.headline)
        .foregroundStyle(.secondary)

      ForEach(localPhases) { phase in
        HStack(spacing: 8) {
          Button {
            togglePhase(at: phase.index)
          } label: {
            Image(systemName: phase.isCompleted ? "checkmark.circle.fill" : "circle")
              .foregroundStyle(phase.isCompleted ? .green : .secondary)
          }
          .buttonStyle(.plain)

          Text(phase.description)
            .font(.body)
            .strikethrough(phase.isCompleted, color: .secondary)
            .foregroundStyle(phase.isCompleted ? .secondary : .primary)
        }
      }
    }
  }

  // MARK: - Completion / Error

  private func completionBanner(_ result: PlanService.ExecuteResult) -> some View {
    let bannerIcon: String
    let bannerColor: Color
    let bannerTitle: String
    if result.allCompleted {
      bannerIcon = "checkmark.circle.fill"
      bannerColor = .green
      bannerTitle = "All phases completed"
    } else if result.stoppedForArchitectureReview {
      bannerIcon = "building.columns"
      bannerColor = .blue
      bannerTitle = "Paused for architecture review"
    } else {
      bannerIcon = "exclamationmark.triangle.fill"
      bannerColor = .orange
      bannerTitle = "Execution stopped"
    }

    return HStack(spacing: 8) {
      Image(systemName: bannerIcon)
        .foregroundStyle(bannerColor)
      VStack(alignment: .leading) {
        Text(bannerTitle)
          .font(.subheadline.bold())
                Text("\(result.phasesExecuted)/\(result.totalPhases) phases in \(formattedTime(result.totalSeconds))")
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Spacer()
      Button("Dismiss") {
        planModel.reset()
      }
      .buttonStyle(.borderless)
    }
    .padding(10)
    .background(bannerColor.opacity(0.1))
    .clipShape(RoundedRectangle(cornerRadius: 8))
  }

  private func errorBanner(_ error: Error) -> some View {
    HStack(spacing: 8) {
      Image(systemName: "exclamationmark.triangle.fill")
        .foregroundStyle(.red)
      Text(error.localizedDescription)
        .font(.callout)
      Spacer()
      Button("Dismiss") {
        planModel.reset()
      }
      .buttonStyle(.borderless)
    }
    .padding(10)
    .background(.red.opacity(0.1))
  }

  // MARK: - Actions

  private func startExecution() {
    let executionModel = planModel.makeChatModel(
      workingDirectory: repository.path.path()
    )
    executionChatModel = executionModel
    panelModel.showOutput(with: executionModel)
    activePlanModel.stopWatching()

    let stopForDiagram = stopAfterArchitectureDiagram
    let mode: PlanService.ExecuteMode = executeNextOnly ? .next : .all
    let worktree = useWorktree
    Task {
      await planModel.execute(
        plan: plan,
        repository: repository,
        chatModel: executionModel,
        executeMode: mode,
        stopAfterArchitectureDiagram: stopForDiagram,
        useWorktree: worktree
      )
    }
  }

  private func handleExecutionComplete() async {
    await loadPlan()
    mergeExecutionPhaseStates()
    executionChatModel?.finalizeCurrentStreamingMessage()
    executionChatModel = nil
    resumeWatchingIfNeeded()
  }

  private func mergeExecutionPhaseStates() {
    let executionPhases = planModel.state.lastExecutionPhases
    guard !executionPhases.isEmpty else { return }
    localPhases = localPhases.enumerated().map { index, phase in
      if index < executionPhases.count, executionPhases[index].isCompleted {
        return PlanPhase(index: phase.index, description: phase.description, isCompleted: true)
      }
      return phase
    }
  }

  private func togglePhase(at index: Int) {
    do {
      let updatedContent = try planModel.togglePhase(plan: plan, phaseIndex: index)
      planContent = updatedContent
      localPhases = PlanPhase.parsePhases(from: updatedContent)
    } catch {
      planModel.reportError(error)
    }
  }

  private func completePlan() {
    do {
      try planModel.completePlan(plan, repository: repository)
    } catch {
      planModel.reportError(error)
    }
  }

  // MARK: - Helpers

  private func loadPlan() async {
    do {
      let content = try await planModel.getPlanDetails(planName: plan.name, repository: repository)
      planContent = content
      editablePlanContent = content
      localPhases = PlanPhase.parsePhases(from: content)
      loadError = nil
    } catch {
      planContent = nil
      editablePlanContent = ""
      localPhases = []
      loadError = error.localizedDescription
    }

    loadArchitectureDiagram()
  }

  private func handleEditingModeChange(_ isEditing: Bool) {
    if isEditing {
      editablePlanContent = planContent ?? ""
      activePlanModel.stopWatching()
      return
    }

    let trimmedOriginal = planContent ?? ""
    guard editablePlanContent != trimmedOriginal else {
      resumeWatchingIfNeeded()
      return
    }

    Task {
      do {
        try await planModel.savePlanContent(editablePlanContent, to: plan.planURL)
        planContent = editablePlanContent
        localPhases = PlanPhase.parsePhases(from: editablePlanContent)
        loadError = nil
      } catch {
        loadError = error.localizedDescription
        editablePlanContent = trimmedOriginal
      }
      resumeWatchingIfNeeded()
    }
  }

  private func resumeWatchingIfNeeded() {
    guard !isEditingMarkdown else { return }
    activePlanModel.startWatching(url: plan.planURL)
  }

  private func loadArchitectureDiagram() {
    let planName = plan.planURL.deletingPathExtension().lastPathComponent
    let architectureURL = plan.planURL
      .deletingLastPathComponent()
      .appendingPathComponent("\(planName)-architecture.json")
    if let data = try? Data(contentsOf: architectureURL) {
      architectureDiagram = try? JSONDecoder().decode(ArchitectureDiagram.self, from: data)
    } else {
      architectureDiagram = nil
    }
    selectedModule = nil
  }

  private func formattedTime(_ totalSeconds: Int) -> String {
    let minutes = totalSeconds / 60
    let seconds = totalSeconds % 60
    if minutes > 0 {
      return "\(minutes)m \(seconds)s"
    }
    return "\(seconds)s"
  }

  private var completedPhaseDescriptions: [String] {
    localPhases.filter(\.isCompleted).map(\.description)
  }

  private var shouldShowDiffSection: Bool {
    !completedPhaseDescriptions.isEmpty
  }

  private var diffSection: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Diff")
        .font(.headline)
        .foregroundStyle(.secondary)

      CommitListDiffView(
        diffService: localDiffService,
        workingDirectoryMonitor: gitWorkingDirectoryMonitor,
        planPhaseDescriptions: completedPhaseDescriptions,
        repoPath: repository.path.path()
      )
      .frame(maxWidth: .infinity, minHeight: 520, alignment: .topLeading)
      .clipShape(RoundedRectangle(cornerRadius: 10))
    }
  }
}

// MARK: - Append Review Popover

private struct AppendReviewPopover: View {
  let plan: MarkdownPlanEntry
  let reviewsDirectory: URL
  let onAppended: () -> Void
  @Environment(PlanModel.self) var planModel
  @Environment(\.dismiss) var dismiss

  @State private var templates: [ReviewTemplate] = []
  @State private var loadError: String?
  @State private var appendedName: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Append Review")
        .font(.headline)

      if let appendedName {
        Label("\(appendedName) appended", systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
          .font(.subheadline)
      } else if let loadError {
        Text(loadError)
          .foregroundStyle(.red)
          .font(.caption)
      } else if templates.isEmpty {
        Text("No templates found in docs/reviews/")
          .foregroundStyle(.secondary)
          .font(.caption)
      } else {
        ForEach(templates) { template in
          Button {
            Task {
              do {
                try await planModel.appendReviewTemplate(template, to: plan.planURL)
                appendedName = template.name
                onAppended()
                try? await Task.sleep(for: .seconds(1))
                dismiss()
              } catch {
                loadError = error.localizedDescription
              }
            }
          } label: {
            Text(template.name)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
          .buttonStyle(.plain)
          .padding(.vertical, 2)
        }
      }
    }
    .padding()
    .frame(minWidth: 220)
    .task {
      do {
        let service = ReviewTemplateService(reviewsDirectory: reviewsDirectory)
        templates = try service.availableTemplates()
      } catch {
        loadError = error.localizedDescription
      }
    }
  }
}
