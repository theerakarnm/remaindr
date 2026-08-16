import Foundation

/// Reads and writes a JSON dotfile in the user's home directory. Never stores secrets -
/// API keys stay in the Keychain. The file lives outside the app bundle and Application
/// Support, so it survives an uninstall the same way Keychain items already do.
struct ConfigFileStore<Value: Codable> {
    private let url: URL

    init(fileName: String, fileManager: FileManager = .default) {
        self.url = fileManager.homeDirectoryForCurrentUser.appendingPathComponent(fileName)
    }

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
