import SwiftUI

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    static let accent = Color(hex: 0xF0362A)
    static let ink = Color(hex: 0x2B1E18)
}

/// Largest rect with the image's aspect ratio that fits `bounds`, centered.
func fittedRect(imageSize: CGSize, in bounds: CGSize, inset: CGFloat = 0) -> CGRect {
    let available = CGSize(width: max(bounds.width - inset * 2, 1), height: max(bounds.height - inset * 2, 1))
    let scale = min(available.width / imageSize.width, available.height / imageSize.height)
    let width = imageSize.width * scale
    let height = imageSize.height * scale
    return CGRect(x: (bounds.width - width) / 2, y: (bounds.height - height) / 2, width: width, height: height)
}

struct EditorScaffold<Canvas: View, Controls: View>: View {
    let title: String
    var saveTitle = "Save"
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let canvas: () -> Canvas
    @ViewBuilder let controls: () -> Controls

    var body: some View {
        VStack(spacing: 12) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(Color.ink.opacity(0.85))
                .padding(.top, 8)
            canvas()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.07)))
                .clipShape(RoundedRectangle(cornerRadius: 14))
            controls()
            HStack {
                Button("Cancel", action: onCancel)
                    .buttonStyle(SoftButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button(saveTitle, action: onSave)
                    .buttonStyle(AccentButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 18)
        .padding(.bottom, 16)
        .background(WarmBackground())
        .ignoresSafeArea(edges: .top)
    }
}

struct WarmBackground: View {
    var body: some View {
        ZStack {
            // Translucent so the window's glass/blur shows through.
            LinearGradient(colors: [Color(hex: 0xFFE9D9, opacity: 0.55), Color(hex: 0xFFCFB0, opacity: 0.45)], startPoint: .top, endPoint: .bottom)
            RadialGradient(colors: [Color(hex: 0xFFB27A, opacity: 0.35), .clear], center: .topTrailing, startRadius: 10, endRadius: 520)
        }
        .ignoresSafeArea()
    }
}

struct AccentButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 8)
            .background(Capsule().fill(LinearGradient(colors: [Color(hex: 0xFF6A3D), Color.accent], startPoint: .top, endPoint: .bottom)))
            .shadow(color: Color.accent.opacity(0.35), radius: 6, y: 3)
            .opacity(configuration.isPressed ? 0.8 : 1)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Color.ink.opacity(0.8))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.45 : 0.7)))
    }
}

struct ChipPicker<Value: Hashable>: View {
    let options: [Value]
    let title: (Value) -> String
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: 6) {
            ForEach(options, id: \.self) { option in
                ToolChip(title: title(option), symbol: nil, selected: selection == option) {
                    selection = option
                }
            }
        }
    }
}

struct ToolChip: View {
    let title: String
    let symbol: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol {
                    Image(systemName: symbol)
                }
                Text(title)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .foregroundStyle(selected ? Color.white : Color.ink.opacity(0.75))
            .background(Capsule().fill(selected ? Color.accent : Color.white.opacity(0.65)))
        }
        .buttonStyle(.plain)
    }
}

struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    var valueText: ((Double) -> String)? = nil

    var body: some View {
        HStack(spacing: 10) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color.ink.opacity(0.65))
                .frame(width: 78, alignment: .leading)
            Slider(value: $value, in: range)
                .tint(Color.accent)
            if let valueText {
                Text(valueText(value))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Color.ink.opacity(0.6))
                    .frame(width: 50, alignment: .trailing)
            }
        }
    }
}

func signedText(_ value: Double) -> String {
    String(format: "%+.2f", value)
}
