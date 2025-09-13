import SwiftUI
import AppKit

struct CLIToggleView: View {
    let name: String
    let logoImageName: String
    let brandColor: Color
    @Binding var isEnabled: Bool
    @Binding var isActive: Bool
    let action: (Bool) -> Void
    let launchAction: (() -> Void)?
    
    // MARK: Environment
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.isEnabled) private var isAppEnabled
    
    // MARK: Private State
    private let buttonSize: CGFloat = 26
    private let imagePadding: CGFloat = 5

    var body: some View {
        HStack {
            Button(action: {
                let newValue = !isActive
                isActive = newValue
                action(newValue)
            }) {
                Circle()
                    .fill(buttonBackgroundColor)
                    .overlay(
                        Image(logoImageName)
                            .resizable()
                            .scaledToFit()
                            .colorMultiply(buttonForegroundColor)
                            .padding(imagePadding)
                    )
                    .animation(.snappy, value: isActive || isAppEnabled)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(!isAppEnabled)
            .frame(width: buttonSize, height: buttonSize)
            
            Text(name)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundColor(isAppEnabled ? Color.primary : .primary.opacity(0.5))
            
            if let launchAction = launchAction, isActive {
                Button(action: launchAction) {
                    Image(systemName: "arrow.up.right.square")
                        .foregroundColor(.secondary)
                        .font(.system(size: 14))
                }
                .buttonStyle(PlainButtonStyle())
                .disabled(!isAppEnabled)
                .help("Launch \(name)")
            }
        }
        .frame(height: buttonSize)
        .padding(.horizontal, 14)
    }
    
    private var buttonBackgroundColor: Color {
        if isActive {
            return .white.opacity(isAppEnabled ? 1.0 : 0.6)
        } else {
            return Color.gray.opacity(isAppEnabled ? 0.6 : 0.3)
        }
    }

    private var buttonForegroundColor: Color {
        if isActive {
            return Color.white // Let the SVG show its true colors when ON
        } else {
            return Color(red: 0.4, green: 0.4, blue: 0.4) // Dark grey multiply when OFF
        }
    }
}