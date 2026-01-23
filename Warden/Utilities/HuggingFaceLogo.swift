import SwiftUI

struct HuggingFaceLogo: View {
    var body: some View {
        // Simple geometric representation of HuggingFace logo
        ZStack {
            Circle()
                .fill(LinearGradient(
                    gradient: Gradient(colors: [.orange, .yellow]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            
            Image(systemName: "brain.head.profile")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white)
        }
    }
}
