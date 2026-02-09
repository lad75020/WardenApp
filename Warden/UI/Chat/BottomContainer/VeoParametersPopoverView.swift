import SwiftUI

// Veo parameters popover used from MessageInputView
// Displays basic controls to tweak video generation parameters.

public struct VeoParametersPopoverView: View {
    @Binding var parameters: VeoUserParameters

    public init(parameters: Binding<VeoUserParameters>) {
        self._parameters = parameters
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Veo Parameters")
                .font(.headline)

            // Aspect Ratio
            HStack {
                Text("Aspect Ratio")
                Spacer()
                Picker("Aspect Ratio", selection: $parameters.aspectRatio) {
                    Text("16:9").tag("16:9")
                    Text("9:16").tag("9:16")
                    Text("1:1").tag("1:1")
                    Text("4:3").tag("4:3")
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }

            // Duration (server supports ~4-10s; handler clamps)
            HStack {
                Text("Duration")
                Spacer()
                Stepper(value: $parameters.durationSeconds, in: 4...10) {
                    Text("\(parameters.durationSeconds)s")
                        .monospacedDigit()
                }
                .labelsHidden()
            }

            // Negative Prompt
            VStack(alignment: .leading, spacing: 6) {
                Text("Negative Prompt")
                TextField("Objects or styles to avoid", text: $parameters.negativePrompt, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
    }
}

#if DEBUG
struct VeoParametersPopoverView_Previews: PreviewProvider {
    @State static var params = VeoUserParameters.default

    static var previews: some View {
        VeoParametersPopoverView(parameters: $params)
            .frame(width: 340)
            .padding()
    }
}
#endif
