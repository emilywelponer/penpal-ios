import Foundation

enum MagazineTemplateLocalization {
    static func localizePages(_ pages: inout [MagazinePage], language: AppLanguage) {
        guard language != .english else { return }
        pages = pages.map { localizePage($0, language: language) }
    }

    static func localizePage(_ page: MagazinePage, language: AppLanguage) -> MagazinePage {
        guard language != .english else { return page }
        var copy = page
        copy.sectionTitle = localizedTemplateText(copy.sectionTitle, language: language)
        copy.elements = copy.elements.map { element in
            var localizedElement = element
            localizedElement.text = localizedTemplateText(element.text, language: language)
            return localizedElement
        }
        return copy
    }

    static func localizedTemplateText(_ text: String, language: AppLanguage) -> String {
        guard language != .english else { return text }
        if text.isEmpty { return text }
        if shouldKeepText(text) { return text }
        return translations(for: language)[text] ?? text
    }

    static func englishLogicText(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return text }
        return reverseTranslations[trimmed] ?? trimmed
    }

    private static func translations(for language: AppLanguage) -> [String: String] {
        switch language {
        case .english:
            return [:]
        case .german:
            return germanTranslations
        case .italian:
            return italianTranslations
        case .spanish:
            return spanishTranslations
        case .french:
            return frenchTranslations
        }
    }

    private static let reverseTranslations: [String: String] = {
        var values: [String: String] = [:]
        for dictionary in [germanTranslations, italianTranslations, spanishTranslations, frenchTranslations] {
            for (english, localized) in dictionary {
                values[localized] = english
            }
        }
        return values
    }()

    private static func shouldKeepText(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if trimmed.hasPrefix("№01") || trimmed.hasPrefix("Nº ") || trimmed.hasPrefix("NO.") { return true }
        if trimmed.allSatisfy({ $0.isNumber || $0.isWhitespace || $0 == "." || $0 == "/" || $0 == "·" || $0 == "№" || $0 == "º" || $0 == "°" }) { return true }
        if trimmed.allSatisfy({ "★☆✦♡♥▢—–·. /_".contains($0) }) { return true }
        if trimmed.hasPrefix("__") { return true }
        if trimmed.contains("/ 10") || trimmed.contains("/10") || trimmed.contains("/31") { return true }
        return false
    }
}

func templateLogicText(_ text: String) -> String {
    MagazineTemplateLocalization.englishLogicText(text)
}
