import CoreData
import SwiftUI

struct GlassMorphicBackground: View {
    let color: Color
    let isSelected: Bool

    var body: some View {
        Rectangle()
            .fill(color)
            .opacity(isSelected ? 0.6 : 0.12)
    }
}

struct PersonaChipView: View {
    let persona: PersonaEntity
    let isSelected: Bool
    @State private var isHovered = false

    private let personaSymbol: String

    init(persona: PersonaEntity, isSelected: Bool) {
        self.persona = persona
        self.isSelected = isSelected
        personaSymbol = persona.color ?? "person.circle"
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: personaSymbol)
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)

            Text(persona.name ?? "Assistant")
                .foregroundStyle(.primary)
        }
        .frame(height: 32)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .opacity(isSelected ? 0.8 : 0.3)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.accentColor, lineWidth: isSelected ? 2 : 0)
                )
                .shadow(
                    color: .accentColor.opacity(isSelected ? 0.3 : (isHovered ? 0.1 : 0)),
                    radius: isSelected ? 4 : 2
                )
        )
        .animation(.easeOut(duration: 0.2), value: isHovered)
        .animation(.easeOut(duration: 0.2), value: isSelected)
        .onHover { isHovered = $0 }
        .padding(4)
    }
}

struct PersonaSelectorView: View {
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \PersonaEntity.order, ascending: true)],
        animation: .default
    )
    private var personas: FetchedResults<PersonaEntity>

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \APIServiceEntity.addedDate, ascending: false)],
        animation: .default
    )
    private var apiServices: FetchedResults<APIServiceEntity>

    @ObservedObject var chat: ChatEntity
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.colorScheme) private var colorScheme
    @State private var selectionError: String?

    private let edgeDarkColor = Color(red: 30 / 255, green: 30 / 255, blue: 30 / 255)
    private let edgeLightColor = Color.white

    private func updatePersona(to persona: PersonaEntity?) {
        let previousPersona = chat.persona
        chat.persona = persona
        chat.objectWillChange.send()

        do {
            try viewContext.save()
            NotificationCenter.default.post(
                name: NSNotification.Name("RecreateMessageManager"),
                object: nil,
                userInfo: ["chatId": chat.id]
            )
        } catch {
            chat.persona = previousPersona
            chat.objectWillChange.send()
            selectionError = "The assistant selection could not be saved."
            WardenLog.coreData.error("Failed to save chat persona selection")
        }
    }

    private func applyDefaultService(for persona: PersonaEntity) {
        guard let service = persona.defaultApiService else { return }
        let modelID = service.model ?? AppConstants.chatGptDefaultModel

        switch ChatModelSelectionCoordinator.apply(
            service: service,
            modelID: modelID,
            to: chat,
            services: Array(apiServices),
            context: viewContext
        ) {
        case .success:
            break
        case .failure(let error):
            selectionError = error.localizedDescription
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            ScrollViewReader { scrollView in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            withAnimation(.easeOut(duration: 0.2)) {
                                updatePersona(to: nil)
                            }
                        } label: {
                            Text("None")
                                .foregroundStyle(.primary)
                                .frame(height: 32)
                                .padding(.horizontal, 12)
                                .background(
                                    RoundedRectangle(cornerRadius: 16)
                                        .fill(chat.persona == nil ? Color.accentColor.opacity(0.6) : Color.gray.opacity(0.12))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .stroke(
                                                    chat.persona == nil ? Color.accentColor.opacity(0.8) : Color.gray.opacity(0.2),
                                                    lineWidth: chat.persona == nil ? 2 : 1
                                                )
                                        )
                                )
                                .padding(4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("No assistant")
                        .accessibilityValue(chat.persona == nil ? "Selected" : "Not selected")

                        ForEach(personas, id: \.objectID) { persona in
                            Button {
                                withAnimation(.easeOut(duration: 0.2)) {
                                    updatePersona(to: persona)
                                }
                            } label: {
                                PersonaChipView(persona: persona, isSelected: chat.persona == persona)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(persona.name ?? "Assistant")
                            .accessibilityValue(chat.persona == persona ? "Selected" : "Not selected")
                            .id(persona.objectID)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .overlay(alignment: .leading) {
                    LinearGradient(
                        colors: [colorScheme == .dark ? edgeDarkColor : edgeLightColor, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 24)
                    .allowsHitTesting(false)
                }
                .overlay(alignment: .trailing) {
                    LinearGradient(
                        colors: [.clear, colorScheme == .dark ? edgeDarkColor : edgeLightColor],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: 24)
                    .allowsHitTesting(false)
                }
                .onAppear {
                    if let selectedPersona = chat.persona {
                        scrollView.scrollTo(selectedPersona.objectID, anchor: .center)
                    }
                }
            }

            if let persona = chat.persona, persona.defaultApiService != nil {
                Button {
                    applyDefaultService(for: persona)
                } label: {
                    Label("Use Assistant Default Service", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .accessibilityHint("Changes the chat model only after checking that the assistant default is available")
            }
        }
        .frame(minHeight: 64)
        .alert("Unable to Update Chat", isPresented: Binding(
            get: { selectionError != nil },
            set: { if !$0 { selectionError = nil } }
        )) {
            Button("OK", role: .cancel) { selectionError = nil }
        } message: {
            Text(selectionError ?? "")
        }
    }
}

#Preview {
    let context = PersistenceController.preview.container.viewContext
    let chat = ChatEntity(context: context)
    return PersonaSelectorView(chat: chat)
        .frame(width: 400)
}
