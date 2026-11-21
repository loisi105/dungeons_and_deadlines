import SwiftUI
import AuthenticationServices
import CryptoKit

/// "Sign in with Apple" for the player's account. Optional: raids work without it, but with it
/// they follow the player to a new phone. Shown only when multiplayer is available.
struct AppleSignInRow: View {
    @Environment(SyncEngine.self) private var sync
    @Environment(\.colorScheme) private var colorScheme
    /// Sent to Apple hashed, and to Firebase raw, so a stolen token can't be replayed.
    @State private var nonce = ""
    @State private var errorMessage: String?

    var body: some View {
        if sync.isAvailable {
            if sync.isAppleLinked {
                Label("Signed in with Apple", systemImage: "apple.logo")
                    .accessibilityIdentifier("appleSignedIn")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    SignInWithAppleButton(.signIn) { request in
                        nonce = Self.randomNonce()
                        request.requestedScopes = []
                        request.nonce = Self.sha256(nonce)
                    } onCompletion: { result in
                        handle(result)
                    }
                    .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
                    .frame(height: 44)
                    .accessibilityIdentifier("signInWithAppleButton")
                    Text("Keeps your raids when you get a new phone. Apple shares nothing with us but a private ID.")
                        .readableFootnote()
                    if let errorMessage {
                        Text(errorMessage).font(.footnote).foregroundStyle(.red)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func handle(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .failure(let error):
            // Cancelling is not an error worth showing.
            if (error as? ASAuthorizationError)?.code != .canceled { errorMessage = error.localizedDescription }
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential,
                  let data = credential.identityToken, let token = String(data: data, encoding: .utf8) else {
                errorMessage = String(localized: "Apple didn't send a sign-in token. Try again.")
                return
            }
            errorMessage = nil
            let raw = nonce
            Task {
                do {
                    try await sync.signInWithApple(identityToken: token, rawNonce: raw)
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private static func randomNonce(length: Int = 32) -> String {
        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        return String((0..<length).map { _ in charset.randomElement()! })
    }

    private static func sha256(_ input: String) -> String {
        SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
