import Foundation

enum NativeStrings {
  private static var shared: UserDefaults? {
    guard let group = Bundle.main.object(forInfoDictionaryKey: "FKNotesAppGroup") as? String,
          FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil else { return nil }
    return UserDefaults(suiteName: group)
  }

  static func setLanguage(_ tag: String) {
    UserDefaults.standard.set(tag, forKey: "fknotes.language")
    shared?.set(tag, forKey: "fknotes.language")
  }

  static func text(_ key: String) -> String {
    let tag = shared?.string(forKey: "fknotes.language") ?? UserDefaults.standard.string(forKey: "fknotes.language") ?? ""
    let language = tag.isEmpty ? Bundle.main.preferredLocalizations.first ?? "en" : tag
    let folder = language.hasPrefix("zh") ? "zh-Hans" : "en"
    guard let path = Bundle.main.path(forResource: folder, ofType: "lproj"), let bundle = Bundle(path: path) else {
      return NSLocalizedString(key, comment: "Native interface")
    }
    return bundle.localizedString(forKey: key, value: nil, table: nil)
  }
}
