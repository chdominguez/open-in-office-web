import Foundation

/// Localized string. Keys are the English text; translations live in Resources/<lang>.lproj/Localizable.strings.
func L(_ key: String, _ args: CVarArg...) -> String {
    let format = NSLocalizedString(key, comment: "")
    return args.isEmpty ? format : String(format: format, arguments: args)
}
