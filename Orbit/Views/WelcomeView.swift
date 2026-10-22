
import SwiftUI

struct WelcomeView: View {
    @State private var isAnimating = false
    
    var body: some View {
        VStack(spacing: 32) {
            // App Icon
            iconView
                .opacity(isAnimating ? 1 : 0)
                .offset(y: isAnimating ? 0 : 20)
            
            VStack(spacing: 24) {
                VStack(spacing: 16) {
                    // App Name
                    Text("welcome.title")
                        .font(.system(size: 32, weight: .bold, design: .default))
                        .foregroundColor(.primary)
                    
                    // Description
                    Text("welcome.description")
                        .font(.system(size: 14, weight: .regular, design: .default))
                        .multilineTextAlignment(.center)
                        .foregroundColor(.secondary)
                        .lineSpacing(4)
                }
                
                // Start Button
                Button(action: {
                    WelcomeWindowController.shared.close()
                    SettingsWindowController.shared.show()
                }) {
                    Text("welcome.start")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(NSColor.windowBackgroundColor)) // Inverted text color
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.primary) // Inverted background
                        .cornerRadius(20)
                }
                .buttonStyle(.plain) // Standard plain style for custom button look
                .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            }
            .opacity(isAnimating ? 1 : 0)
            .offset(y: isAnimating ? 0 : 20)
            .animation(.easeOut(duration: 0.8).delay(0.2), value: isAnimating)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor)) // Standard window background
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                isAnimating = true
            }
        }
    }
    
    private var iconView: some View {
        Group {
            if let nsImage = NSApplication.shared.applicationIconImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 128, height: 128)
                    .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
            } else {
                // Fallback if icon is missing
                Circle()
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 128, height: 128)
            }
        }
    }
}

#Preview {
    WelcomeView()
        .frame(width: 400, height: 500)
}
