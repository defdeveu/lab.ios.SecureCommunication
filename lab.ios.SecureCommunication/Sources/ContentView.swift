import SwiftUI

struct ContentView: View {
    @State private var viewModel: ContentViewModel

    @MainActor
    init(viewModel: ContentViewModel = AppRepository.makeViewModel()) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        @Bindable var viewModel = viewModel

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                introduction

                GroupBox("Message") {
                    TextEditor(text: $viewModel.message)
                        .frame(minHeight: 110)
                        .font(.body.monospaced())
                        .accessibilityLabel("Message to encrypt")
                }

                HStack(spacing: 12) {
                    Button("Encrypt and send", systemImage: "lock.shield", action: viewModel.sendMessage)
                        .buttonStyle(SolidButtonStyle())
                        .disabled(viewModel.isLoading)
                    if viewModel.isLoading {
                        Button("Cancel", role: .cancel, action: viewModel.cancelRequest)
                            .buttonStyle(.bordered)
                    }
                }

                status
                responseSection(
                    title: "Encrypted wire response",
                    value: viewModel.rawResponse,
                    placeholder: "No response received yet."
                )
                responseSection(
                    title: "Authenticated plaintext",
                    value: viewModel.decryptedResponse,
                    placeholder: "A valid response will be decrypted here."
                )
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(24)
        }
        .navigationTitle(AppStrings.appTitle)
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                AppImages.appTitleImage
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(.primary)
                    .frame(width: 38, height: 38)
                    .accessibilityHidden(true)
            }
        }
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Protect a message above the transport layer")
                .font(.title2.bold())
            Text("The app creates a fresh symmetric key, encrypts the message, signs the envelope, and authenticates the encrypted reply.")
                .foregroundStyle(.secondary)
        }
    }

    private var status: some View {
        GroupBox("Status") {
            HStack(spacing: 12) {
                if viewModel.isLoading {
                    ProgressView()
                        .accessibilityLabel("Request in progress")
                }
                Text(viewModel.status)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.top, 4)
        }
    }

    private func responseSection(title: String, value: String?, placeholder: String) -> some View {
        GroupBox(title) {
            Text(value ?? placeholder)
                .font(.body.monospaced())
                .foregroundStyle(value == nil ? .secondary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
        }
    }
}

struct ContentViewPreviews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            ContentView()
        }
    }
}
