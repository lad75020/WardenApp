import SwiftUI

/// Recovery controls for retained history whose service is unavailable.
/// The view deliberately receives only Core Data entities and never credentials.
struct UnavailableChatRecoveryView: View {
    @ObservedObject var chat: ChatEntity
    let availability: ChatServiceAvailability
    let candidates: [APIServiceEntity]
    let onRepair: (APIServiceEntity) -> Void
    let onOpenServiceSettings: () -> Void
    let onDelete: () -> Void

    @State private var selectedServiceID: UUID?
    @State private var showingDeleteConfirmation = false
    @State private var failureMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Chat unavailable", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .accessibilityLabel("Chat unavailable")
                .accessibilityIdentifier("persistenceRecovery.unavailableSummary")

            Text(availability.recoverySummary)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sending is disabled until this chat is repaired.")
                .font(.subheadline)
                .accessibilityLabel("Sending is disabled until this chat is repaired")
                .accessibilityIdentifier("persistenceRecovery.sendingDisabled")

            if candidates.isEmpty {
                Text("No usable service is currently configured. Add or repair a service in Settings, then choose Repair.")
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Open Service Settings", action: onOpenServiceSettings)
                    .accessibilityLabel("Open Service Settings")
                    .accessibilityIdentifier("persistenceRecovery.openSettings")
                    .keyboardShortcut(",", modifiers: .command)
            } else {
                Picker("Repair using", selection: $selectedServiceID) {
                    Text("Choose a service").tag(UUID?.none)
                    ForEach(candidates, id: \.objectID) { service in
                        Text(service.name ?? "Configured service").tag(service.id)
                    }
                }
                .accessibilityLabel("Choose a service to repair this chat")
                .accessibilityIdentifier("persistenceRecovery.servicePicker")

                Button("Repair Chat") {
                    guard let selectedServiceID,
                          let service = candidates.first(where: { $0.id == selectedServiceID }) else {
                        failureMessage = "Choose a service before repairing this chat."
                        return
                    }
                    onRepair(service)
                }
                .disabled(selectedServiceID == nil)
                .accessibilityLabel("Repair chat using selected service")
                .accessibilityIdentifier("persistenceRecovery.repair")
                .keyboardShortcut(.defaultAction)
            }

            if let failureMessage {
                Text(failureMessage)
                    .font(.subheadline)
                    .accessibilityLabel("Recovery action failed. \(failureMessage)")
                    .accessibilityIdentifier("persistenceRecovery.failure")
            }

            Button("Delete Chat", role: .destructive) {
                showingDeleteConfirmation = true
            }
            .accessibilityLabel("Delete unavailable chat")
            .accessibilityIdentifier("persistenceRecovery.delete")
            .alert("Delete this unavailable chat?", isPresented: $showingDeleteConfirmation) {
                Button("Delete", role: .destructive, action: onDelete)
                    .accessibilityLabel("Confirm deletion of unavailable chat")
                Button("Cancel", role: .cancel) { }
                    .accessibilityLabel("Cancel deletion")
            } message: {
                Text("This permanently removes the chat and its local history.")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("persistenceRecovery.container")
    }
}
