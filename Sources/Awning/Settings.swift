import Foundation

/// Persisted preferences (UserDefaults).
final class Settings {
    static let shared = Settings()
    /// Everything Awning writes lives in one folder, so it can be synced or put under git as a unit.
    static let homeFolderPath = "~/.awning"
    static let defaultNotesPath = homeFolderPath + "/notes.txt"

    static var homeFolder: URL {
        URL(fileURLWithPath: (homeFolderPath as NSString).expandingTildeInPath, isDirectory: true)
    }

    private let defaults = UserDefaults.standard

    var notesPath: String {
        get { defaults.string(forKey: "notesPath") ?? Self.defaultNotesPath }
        set { defaults.set(newValue, forKey: "notesPath") }
    }

    var notesURL: URL {
        URL(fileURLWithPath: (notesPath as NSString).expandingTildeInPath)
    }

    var hotKeyID: String {
        get { defaults.string(forKey: "hotKey") ?? HotKeyPreset.all[0].id }
        set { defaults.set(newValue, forKey: "hotKey") }
    }

    /// 0 means "pick a height from the screen size".
    var visorHeight: Double {
        get { defaults.double(forKey: "visorHeight") }
        set { defaults.set(newValue, forKey: "visorHeight") }
    }

    static let defaultFontSize = 14.0
    var fontSize: Double {
        get { defaults.object(forKey: "fontSize") as? Double ?? Self.defaultFontSize }
        set { defaults.set(newValue, forKey: "fontSize") }
    }

    var appearance: AppearanceMode {
        get { defaults.string(forKey: "appearance").flatMap(AppearanceMode.init) ?? .system }
        set { defaults.set(newValue.rawValue, forKey: "appearance") }
    }

    var keepOpenWhenUnfocused: Bool {
        get { defaults.bool(forKey: "keepOpen") }
        set { defaults.set(newValue, forKey: "keepOpen") }
    }

    var hasLaunchedBefore: Bool {
        get { defaults.bool(forKey: "hasLaunchedBefore") }
        set { defaults.set(newValue, forKey: "hasLaunchedBefore") }
    }

    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        return path.hasPrefix(home + "/") ? "~" + path.dropFirst(home.count) : path
    }

    static var conflictsDirectory: URL {
        homeFolder.appendingPathComponent("conflicts", isDirectory: true)
    }
}
