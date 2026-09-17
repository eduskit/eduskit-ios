import Foundation

/// UI Kit 文案访问入口；语言表与业务组件分离。
public enum EduI18n {
    private static var localeTag: String = Locale.current.identifier

    public static func setLocale(_ tag: String?) {
        localeTag = tag?.isEmpty == false ? tag! : Locale.current.identifier
    }

    public static func text(
        _ key: String,
        _ params: [String: CustomStringConvertible] = [:],
        localeTag overrideLocaleTag: String? = nil
    ) -> String {
        let resolvedLocaleTag = overrideLocaleTag?.isEmpty == false ? overrideLocaleTag! : localeTag
        let catalog = resolvedLocaleTag.lowercased().hasPrefix("en") ? EduStringsEnUs : EduStringsZhCn
        var value = catalog[key] ?? EduStringsZhCn[key] ?? key
        for (name, replacement) in params {
            value = value.replacingOccurrences(of: "{\(name)}", with: replacement.description)
        }
        return value
    }
}
