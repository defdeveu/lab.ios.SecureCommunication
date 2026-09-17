import SwiftUI

struct SolidButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .frame(maxWidth: .infinity, minHeight: 52)
            .padding(.horizontal, 16)
            .foregroundStyle(.white)
            .background(.tint, in: RoundedRectangle(cornerRadius: 14))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

enum AppStrings {
    static let appTitle = "Secure Communication Lab"
}

enum AppImages {
    static let appTitleImage = Image("logo.ddd.stamp.1905")
}
