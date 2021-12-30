import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel = ContentViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                TextField("message", text: $viewModel.message)
                    .padding([.leading, .trailing], 10)
                    .frame(height: 44)
                    .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .stroke(AppColors.textInputOverlay, lineWidth: 1))

                Button("Send message", action: viewModel.sendMessage)
                    .buttonStyle(SolidButtonStyle())
                    .disabled(viewModel.response.isInProgress)

                Text("Response:")
                    .font(.title3)
                    .foregroundColor(AppColors.textTitle)
                    .fixedSize(horizontal: false, vertical: true)

                Text(viewModel.response.description)
                    .foregroundColor(AppColors.textOutput)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer()
            }
            .padding()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { appTitle() }
    }

    @ToolbarContentBuilder
    private func appTitle() -> some ToolbarContent {
        ToolbarItem(placement: .navigationBarLeading) {
            HStack {
                AppImages.appTitleImage
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .colorInvert()
                // TODO colorInvert as per the scheme
                Text(AppStrings.appTitle)
                    .font(.title.bold())
                    .foregroundColor(AppColors.navigationForeground)
            }
            .padding(.bottom, 8)
        }
    }
}

#if DEBUG
@available(iOS 15.0, *)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
            .previewInterfaceOrientation(.landscapeLeft)
    }
}
#endif
