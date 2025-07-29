import SwiftUI

struct SunExposurePanel: View {
    @Binding var exposure: Float
    @Binding var blackPoint: Float
    @Binding var shadows: Float
    var onApply: (String) -> Void

    // For display
    let blackRange = 0...4096
    let blackDefault = 2048

    // Generate current PP3 string
    func currentPP3() -> String {
        """
        [Exposure]
        Compensation = \(String(format: "%.2f", exposure))
        Black = \(Int(blackPoint))
        Shadows = \(String(format: "%.2f", shadows))

        [RAW]
        """
    }

    var body: some View {
        VStack(spacing: 20) {
            // Exposure
            VStack(alignment: .leading) {
                Text("Exposure Compensation: \(String(format: "%.2f", exposure))")
                    .shadow(color: .white, radius: 1, x: 0, y: 1)
                Slider(value: $exposure, in: -5.0...5.0, step: 0.1)
            }

            VStack(alignment: .leading) {
                Text("Black Point: \(Int(blackPoint))")
                    .shadow(color: .white, radius: 1, x: 0, y: 1)
                Slider(
                    value: $blackPoint,
                    in: -400.0...400.0,
                    step: 1.0
                )
            }

            // Shadows
            VStack(alignment: .leading) {
                Text("Shadows: \(String(format: "%.2f", shadows))")
                    .shadow(color: .white, radius: 1, x: 0, y: 1)
                Slider(value: $shadows, in: 0.0...100.0, step: 0.1)
            }

            Button("Apply Adjustments") {
                onApply(currentPP3())
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }
}
