import CoreData
import SwiftUI

struct FavoriteQuickAccessBar: View {
    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext

    @StateObject private var favoriteManager = FavoriteModelsManager.shared
    @State private var selectionError: String?

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    private var topFavorites: [ModelSelectionIdentity] {
        let visible = ModelSelectionPolicy.visibleModels(for: Array(apiServices))
        return favoriteManager.getAllFavorites()
            .filter { visible.contains($0) }
            .prefix(4)
            .map { $0 }
    }

    var body: some View {
        Group {
            if !topFavorites.isEmpty {
                HStack(spacing: 6) {
                    ForEach(topFavorites) { favorite in
                        favoriteButton(favorite)
                    }
                }
            }
        }
        .alert(
            "Model Not Changed",
            isPresented: Binding(
                get: { selectionError != nil },
                set: { if !$0 { selectionError = nil } }
            )
        ) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: {
            Text(selectionError ?? "")
        }
    }

    private func favoriteButton(_ favorite: ModelSelectionIdentity) -> some View {
        Button {
            guard let service = apiServices.first(where: { $0.type == favorite.provider }) else {
                selectionError = "This service is no longer configured."
                return
            }

            switch ChatModelSelectionCoordinator.apply(
                service: service,
                modelID: favorite.modelID,
                to: chat,
                services: Array(apiServices),
                context: viewContext
            ) {
            case .success:
                break
            case .failure(let error):
                selectionError = error.localizedDescription
            }
        } label: {
            HStack(spacing: 6) {
                Image("logo_\(favorite.provider)")
                    .resizable()
                    .renderingMode(.template)
                    .interpolation(.high)
                    .frame(width: 12, height: 12)
                    .foregroundStyle(.white)

                Text(favorite.modelID)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(isCurrentlySelected(favorite) ? Color.accentColor : Color.blue.opacity(0.8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isCurrentlySelected(favorite) ? Color.accentColor.opacity(0.6) : Color.blue.opacity(0.4),
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Use favorite model \(favorite.modelID)")
        .accessibilityValue(isCurrentlySelected(favorite) ? "Selected" : "Not selected")
        .help("Switch to \(favorite.modelID)")
    }

    private func isCurrentlySelected(_ favorite: ModelSelectionIdentity) -> Bool {
        chat.apiService?.type == favorite.provider && chat.gptModel == favorite.modelID
    }
}

#Preview {
    FavoriteQuickAccessBar(chat: PreviewStateManager.shared.sampleChat)
        .environmentObject(PreviewStateManager.shared.chatStore)
        .environment(\.managedObjectContext, PreviewStateManager.shared.persistenceController.container.viewContext)
}
