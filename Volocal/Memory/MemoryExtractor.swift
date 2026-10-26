import Foundation

/// Deterministic FR/EN/ES fact extractor. One user turn yields at most one sentence.
/// It never calls a model and never writes a fact about the assistant.
enum MemoryExtractor {
    static func extract(from utterance: String) -> MemoryDraft? {
        let text = normalize(utterance)
        guard text.count >= 3 else { return nil }
        if let draft = extractName(text) { return draft }
        if let draft = extractAge(text) { return draft }
        if let draft = extractGender(text) { return draft }
        if let draft = extractPerson(text) { return draft }
        if let draft = extractPet(text) { return draft }
        if let draft = extractHome(text) { return draft }
        if let draft = extractJob(text) { return draft }
        if let draft = extractLanguage(text) { return draft }
        if let draft = extractProject(text) { return draft }
        if let draft = extractPreference(text) { return draft }
        return nil
    }

    // MARK: - Name

    private static func extractName(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(namePhrases, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        let rest = String(text[hit.range.upperBound...])
        guard let name = takeName(rest) else { return nil }
        let sentence: String
        switch hit.spec.language {
        case .fr: sentence = "L'utilisateur s'appelle \(name)."
        case .en: sentence = "The user's name is \(name)."
        case .es: sentence = "El usuario se llama \(name)."
        }
        return MemoryDraft(category: MemoryCategory.name, key: "name", text: sentence)
    }

    // MARK: - Age and gender

    private static func extractAge(_ text: String) -> MemoryDraft? {
        let patterns: [(String, MemoryLanguage)] = [
            (#"(?i)(?<!\p{L})j'ai\s+(\d{1,3})\s+ans\b"#, .fr),
            (#"(?i)(?<!\p{L})i am\s+(\d{1,3})\s+years?\s+old\b"#, .en),
            (#"(?i)(?<!\p{L})i'm\s+(\d{1,3})\s+years?\s+old\b"#, .en),
            (#"(?i)(?<!\p{L})im\s+(\d{1,3})\s+years?\s+old\b"#, .en),
            (#"(?i)(?<!\p{L})tengo\s+(\d{1,3})\s+años\b"#, .es),
            (#"(?i)(?<!\p{L})tengo\s+(\d{1,3})\s+anos\b"#, .es),
            (#"(?i)(?<!\p{L})my age is\s+(\d{1,3})\b"#, .en),
        ]
        for (pattern, language) in patterns {
            guard let groups = firstGroups(pattern, in: text), groups.count >= 2,
                  let years = Int(groups[1]), (1...120).contains(years) else { continue }
            guard let whole = rangeOfMatch(pattern, in: text), !isNegated(text, before: whole.lowerBound) else {
                continue
            }
            let sentence: String
            switch language {
            case .fr: sentence = "L'utilisateur a \(years) ans."
            case .en: sentence = "The user is \(years) years old."
            case .es: sentence = "El usuario tiene \(years) años."
            }
            return MemoryDraft(category: MemoryCategory.age, key: "age", text: sentence)
        }
        return nil
    }

    private static func extractGender(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(genderPhrases, in: text),
              !isNegated(text, before: hit.range.lowerBound),
              remainderIsClauseBoundary(text, after: hit.range) else { return nil }
        let sentence: String
        switch (hit.spec.language, hit.spec.code) {
        case (.fr, "man"): sentence = "L'utilisateur est un homme."
        case (.fr, "woman"): sentence = "L'utilisateur est une femme."
        case (.fr, "nonbinary"): sentence = "L'utilisateur est non-binaire."
        case (.en, "man"): sentence = "The user is a man."
        case (.en, "woman"): sentence = "The user is a woman."
        case (.en, "nonbinary"): sentence = "The user is non-binary."
        case (.es, "man"): sentence = "El usuario es un hombre."
        case (.es, "woman"): sentence = "El usuario es una mujer."
        case (.es, "nonbinary"): sentence = "El usuario es no binario."
        default: return nil
        }
        return MemoryDraft(category: MemoryCategory.gender, key: "gender", text: sentence)
    }

    // MARK: - People and pets

    private static func extractPerson(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(relations, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        let rest = String(text[hit.range.upperBound...])
        guard let captured = interpretValue(rest) else { return nil }
        let key = personKey(base: hit.spec.key, captured: captured)
        let sentence = renderCaptured(captured, subject: hit.spec.subject, language: hit.spec.language)
        return MemoryDraft(category: MemoryCategory.person, key: key, text: sentence)
    }

    private static func extractPet(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(pets, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        let rest = String(text[hit.range.upperBound...])
        if let captured = interpretValue(rest) {
            let sentence = renderCaptured(captured, subject: hit.spec.subject, language: hit.spec.language)
            return MemoryDraft(category: MemoryCategory.pet, key: hit.spec.key, text: sentence)
        }
        let trimmed = trimValue(rest)
        guard hit.spec.allowsBare, trimmed.isEmpty || leadingClause(trimmed) else { return nil }
        return MemoryDraft(category: MemoryCategory.pet, key: hit.spec.key, text: hit.spec.exists)
    }

    // MARK: - Home, job, language, project

    private static func extractHome(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(homes, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        guard let place = takePlace(String(text[hit.range.upperBound...])) else { return nil }
        return MemoryDraft(category: MemoryCategory.home, key: "home", text: hit.spec.render(place))
    }

    private static func extractJob(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(jobs, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        guard let role = takeJob(String(text[hit.range.upperBound...])) else { return nil }
        return MemoryDraft(category: MemoryCategory.job, key: "job", text: hit.spec.render(role))
    }

    private static func extractLanguage(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(languagePhrases, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        guard let spoken = takeLanguages(String(text[hit.range.upperBound...])) else { return nil }
        let names = spoken.map(\.display)
        let list: String
        switch hit.spec.language {
        case .fr: list = names.joined(separator: " et ")
        case .en: list = joinEnglish(names)
        case .es: list = names.joined(separator: " y ")
        }
        let sentence: String
        switch hit.spec.language {
        case .fr: sentence = "L'utilisateur parle \(list)."
        case .en: sentence = "The user speaks \(list)."
        case .es: sentence = "El usuario habla \(list)."
        }
        let code = spoken.map(\.code).sorted().joined(separator: "+")
        return MemoryDraft(category: MemoryCategory.language, key: "language.\(code)", text: sentence)
    }

    private static func extractProject(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(projects, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        guard let project = takeProject(String(text[hit.range.upperBound...])) else { return nil }
        let slug = slugKey(project)
        guard !slug.isEmpty else { return nil }
        return MemoryDraft(
            category: MemoryCategory.project,
            key: "project.\(slug)",
            text: hit.spec.render(project)
        )
    }

    // MARK: - Preference and limit

    private static func extractPreference(_ text: String) -> MemoryDraft? {
        guard let hit = firstHit(preferences, in: text), !isNegated(text, before: hit.range.lowerBound) else {
            return nil
        }
        guard let object = takeObject(String(text[hit.range.upperBound...])) else { return nil }
        let slug = slugKey(object)
        guard !slug.isEmpty else { return nil }
        let sentence = preferenceSentence(hit.spec.kind, language: hit.spec.language, object: object)
        let category = hit.spec.kind == .prefer ? MemoryCategory.preference : MemoryCategory.limit
        let prefix = hit.spec.kind == .prefer ? "preference" : "limit"
        return MemoryDraft(category: category, key: "\(prefix).\(slug)", text: sentence)
    }

    // MARK: - Value parsing

    private static func interpretValue(_ raw: String) -> Captured? {
        let value = trimValue(raw)
        guard !value.isEmpty, !hasLeadingNegation(value) else { return nil }
        let lower = value.lowercased()
        let intros = [
            "qui s'appelle ", "que se llama ", "s'appelle ", "se llama ",
            "is named ", "is called ", "'s name is ", "name is ", "named ", "called ",
        ]
        for intro in intros where lower.hasPrefix(intro) {
            guard let name = takeName(String(value.dropFirst(intro.count))) else { return nil }
            return .name(name)
        }
        for copula in ["sont ", "son ", "are ", "est ", "is ", "es "] where lower.hasPrefix(copula) {
            guard let description = takeDescription(String(value.dropFirst(copula.count))) else { return nil }
            return .description(description)
        }
        guard let name = takeName(value) else { return nil }
        return .name(name)
    }

    private static func renderCaptured(_ captured: Captured, subject: String, language: MemoryLanguage) -> String {
        switch captured {
        case .name(let name):
            switch language {
            case .fr: return "\(subject) s'appelle \(name)."
            case .en: return "\(subject) is named \(name)."
            case .es: return "\(subject) se llama \(name)."
            }
        case .description(let value):
            switch language {
            case .fr: return "\(subject) est \(value)."
            case .en: return "\(subject) is \(value)."
            case .es: return "\(subject) es \(value)."
            }
        }
    }

    private static func personKey(base: String, captured: Captured) -> String {
        let individual: Set<String> = [
            "person.friend", "person.brother", "person.sister", "person.son", "person.daughter", "person.child",
        ]
        guard individual.contains(base), case .name(let name) = captured else { return base }
        let slug = slugKey(name)
        guard !slug.isEmpty else { return base }
        return base + "." + slug
    }

    private static func takeName(_ raw: String) -> String? {
        guard let tokens = takeTokens(raw, max: 3, allowDigits: false, stopAtConjunction: true) else { return nil }
        guard let first = tokens.first?.lowercased(), !nameStopwords.contains(first), !vagueObjects.contains(first) else {
            return nil
        }
        return tokens.map(displayName).joined(separator: " ")
    }

    private static func takePlace(_ raw: String) -> String? {
        guard let tokens = takeTokens(raw, max: 6, allowDigits: true, stopAtConjunction: true) else { return nil }
        let place = displayPlace(tokens)
        guard place.count >= 2, !placeChatter.contains(place.lowercased()) else { return nil }
        return place
    }

    private static func takeJob(_ raw: String) -> String? {
        guard let tokens = takeTokens(raw, max: 6, allowDigits: true, stopAtConjunction: false) else { return nil }
        var core = tokens
        while let first = core.first?.lowercased(), jobArticles.contains(first) {
            core.removeFirst()
        }
        guard let head = core.first?.lowercased(), !jobChatter.contains(head), core.joined(separator: " ").count >= 2 else {
            return nil
        }
        return soften(tokens.joined(separator: " "))
    }

    private static func takeProject(_ raw: String) -> String? {
        guard let tokens = takeTokens(raw, max: 6, allowDigits: true, stopAtConjunction: true) else { return nil }
        var core = tokens
        while let first = core.first?.lowercased(), jobArticles.contains(first) {
            core.removeFirst()
        }
        guard let head = core.first?.lowercased(), !vagueObjects.contains(head) else { return nil }
        let project = tokens.joined(separator: " ")
        guard project.count >= 2 else { return nil }
        return project
    }

    private static func takeObject(_ raw: String) -> String? {
        guard let tokens = takeTokens(raw, max: 8, allowDigits: true, stopAtConjunction: false) else { return nil }
        guard let head = tokens.first?.lowercased(), !vagueObjects.contains(head) else { return nil }
        let object = soften(tokens.joined(separator: " "))
        guard object.count >= 2 else { return nil }
        return object
    }

    private static func takeLanguages(_ raw: String) -> [LanguageName]? {
        let trimmed = trimValue(raw)
        guard !trimmed.isEmpty, !hasLeadingNegation(trimmed) else { return nil }
        var found: [LanguageName] = []
        var seen = Set<String>()
        for token in trimmed.split(separator: " ") {
            let lower = stripEdgePunctuation(String(token)).lowercased()
            if lower.isEmpty { break }
            if languageSkip.contains(lower) { continue }
            if conjunctions.contains(lower) { continue }
            guard let language = languageNames[lower] else {
                if found.isEmpty { return nil }
                break
            }
            if seen.insert(language.code).inserted {
                found.append(language)
            }
            if found.count == 4 { break }
        }
        return found.isEmpty ? nil : found
    }

    private static func takeTokens(
        _ raw: String,
        max: Int,
        allowDigits: Bool,
        stopAtConjunction: Bool
    ) -> [String]? {
        let trimmed = trimValue(raw)
        guard !trimmed.isEmpty, !hasLeadingNegation(trimmed) else { return nil }
        var tokens: [String] = []
        for part in trimmed.split(separator: " ") {
            let clean = stripEdgePunctuation(String(part))
            if clean.isEmpty { break }
            let lower = clean.lowercased()
            if stopAtConjunction && conjunctions.contains(lower) { break }
            guard isWordToken(clean, allowDigits: allowDigits) else { break }
            tokens.append(clean)
            if tokens.count == max { break }
        }
        return tokens.isEmpty ? nil : tokens
    }

    private static func takeDescription(_ raw: String) -> String? {
        guard let tokens = takeTokens(raw, max: 8, allowDigits: true, stopAtConjunction: false) else { return nil }
        guard let head = tokens.first?.lowercased(), !vagueObjects.contains(head) else { return nil }
        return tokens.joined(separator: " ")
    }

    // MARK: - Text cleanup

    private static func normalize(_ raw: String) -> String {
        var text = raw
        let apostrophes = ["\u{2019}", "\u{2018}", "\u{201B}", "\u{02BC}", "\u{00B4}", "`"]
        for mark in apostrophes {
            text = text.replacingOccurrences(of: mark, with: "'")
        }
        text = text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func trimValue(_ raw: String) -> String {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let regex = compile(#"(?i)\s+(?:et\s+j['e]|et\s+mon\b|et\s+ma\b|et\s+mes\b|and\s+i\b|and\s+my\b|y\s+yo\b|y\s+mi\b|pero\s+|mais\s+|but\s+)"#),
           let match = regex.firstMatch(in: value, range: nsRange(value)),
           let range = Range(match.range, in: value) {
            value = String(value[..<range.lowerBound])
        }
        if let regex = compile(#"[.!?]"#),
           let match = regex.firstMatch(in: value, range: nsRange(value)),
           let range = Range(match.range, in: value) {
            value = String(value[..<range.lowerBound])
        }
        return value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,;:\"“”«»"))
    }

    private static func stripEdgePunctuation(_ token: String) -> String {
        token.trimmingCharacters(in: CharacterSet.punctuationCharacters.union(.symbols))
    }

    private static func isWordToken(_ token: String, allowDigits: Bool) -> Bool {
        guard !token.isEmpty else { return false }
        let extra = allowDigits ? CharacterSet.decimalDigits : CharacterSet()
        let allowed = CharacterSet.letters.union(extra).union(CharacterSet(charactersIn: "-'"))
        return token.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    private static func displayName(_ token: String) -> String {
        let letters = token.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        guard !letters.isEmpty else { return token }
        let allLower = letters.allSatisfy { CharacterSet.lowercaseLetters.contains($0) }
        let allUpper = letters.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
        guard allLower || allUpper else { return token }
        return token.split(separator: "-").map { part -> String in
            let word = String(part)
            guard let first = word.first else { return word }
            return String(first).uppercased() + word.dropFirst().lowercased()
        }.joined(separator: "-")
    }

    private static func displayPlace(_ tokens: [String]) -> String {
        tokens.enumerated().map { index, token in
            let lower = token.lowercased()
            if index > 0 && placeParticles.contains(lower) { return lower }
            return displayName(token)
        }.joined(separator: " ")
    }

    private static func soften(_ raw: String) -> String {
        let letters = raw.unicodeScalars.filter { CharacterSet.letters.contains($0) }
        let allUpper = !letters.isEmpty && letters.allSatisfy { CharacterSet.uppercaseLetters.contains($0) }
        return allUpper ? raw.lowercased() : raw
    }

    private static func slugKey(_ raw: String) -> String {
        var tokens = raw.split(separator: " ").map { stripEdgePunctuation(String($0)).lowercased() }
        while let first = tokens.first, jobArticles.contains(first) || first == "de" || first == "d" {
            tokens.removeFirst()
        }
        let folded = tokens.joined(separator: " ").folding(
            options: [.diacriticInsensitive, .caseInsensitive],
            locale: Locale(identifier: "en_US_POSIX")
        )
        var slug = ""
        var dash = false
        for scalar in folded.unicodeScalars {
            if CharacterSet.alphanumerics.contains(scalar) {
                slug.unicodeScalars.append(scalar)
                dash = false
            } else if !dash && !slug.isEmpty {
                slug.append("-")
                dash = true
            }
        }
        while slug.hasSuffix("-") { slug.removeLast() }
        return slug
    }

    private static func joinEnglish(_ names: [String]) -> String {
        guard names.count > 1 else { return names.first ?? "" }
        if names.count == 2 { return "\(names[0]) and \(names[1])" }
        return names.dropLast().joined(separator: ", ") + ", and " + names[names.count - 1]
    }

    private static func preferenceSentence(
        _ kind: PreferenceKind,
        language: MemoryLanguage,
        object: String
    ) -> String {
        switch (kind, language) {
        case (.prefer, .fr): return "L'utilisateur préfère \(object)."
        case (.prefer, .en): return "The user prefers \(object)."
        case (.prefer, .es): return "El usuario prefiere \(object)."
        case (.dislike, .fr): return "L'utilisateur n'aime pas \(object)."
        case (.dislike, .en): return "The user does not like \(object)."
        case (.dislike, .es): return "Al usuario no le gusta \(object)."
        case (.allergy, .fr): return "L'utilisateur est allergique à \(object)."
        case (.allergy, .en): return "The user is allergic to \(object)."
        case (.allergy, .es): return "El usuario es alérgico a \(object)."
        case (.avoid, .fr): return "L'utilisateur évite \(object)."
        case (.avoid, .en): return "The user avoids \(object)."
        case (.avoid, .es): return "El usuario evita \(object)."
        }
    }

    private static func hasLeadingNegation(_ value: String) -> Bool {
        guard let first = value.split(separator: " ").first else { return false }
        return negationTokens.contains(first.lowercased())
    }

    private static func isNegated(_ text: String, before index: String.Index) -> Bool {
        let prefix = text[..<index]
        let tokens = prefix.split(separator: " ").suffix(3).map { $0.lowercased() }
        return tokens.contains(where: { negationTokens.contains($0) })
    }

    private static func remainderIsClauseBoundary(_ text: String, after range: Range<String.Index>) -> Bool {
        let rest = text[range.upperBound...].trimmingCharacters(in: .whitespaces)
        guard let first = rest.first else { return true }
        if ".!?,;".contains(first) { return true }
        let lower = rest.lowercased()
        return ["et ", "and ", "y ", "mais ", "but ", "pero ", "puis "].contains { lower.hasPrefix($0) }
    }

    private static func leadingClause(_ value: String) -> Bool {
        guard let first = value.split(separator: " ").first else { return true }
        let lower = first.lowercased()
        return conjunctions.contains(lower) || ["mais", "pero", "but"].contains(lower)
    }

    // MARK: - Matching

    private static func firstHit<Spec>(_ specs: [Spec], in text: String) -> Hit<Spec>? where Spec: PhraseSpec {
        var best: Hit<Spec>?
        for spec in specs {
            guard let range = phraseRange(spec.phrase, in: text) else { continue }
            if let current = best {
                let earlier = range.lowerBound < current.range.lowerBound
                let sameAndLonger = range.lowerBound == current.range.lowerBound
                    && spec.phrase.count > current.spec.phrase.count
                if earlier || sameAndLonger {
                    best = Hit(spec: spec, range: range)
                }
            } else {
                best = Hit(spec: spec, range: range)
            }
        }
        return best
    }

    private static func phraseRange(_ phrase: String, in text: String) -> Range<String.Index>? {
        let pattern = "(?i)(?<!\\p{L})" + NSRegularExpression.escapedPattern(for: phrase) + "(?!\\p{L})"
        return rangeOfMatch(pattern, in: text)
    }

    private static func rangeOfMatch(_ pattern: String, in text: String) -> Range<String.Index>? {
        guard let regex = compile(pattern),
              let match = regex.firstMatch(in: text, range: nsRange(text)),
              let range = Range(match.range, in: text) else { return nil }
        return range
    }

    private static func firstGroups(_ pattern: String, in text: String) -> [String]? {
        guard let regex = compile(pattern),
              let match = regex.firstMatch(in: text, range: nsRange(text)) else { return nil }
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            if range.location == NSNotFound {
                groups.append("")
                continue
            }
            guard let swiftRange = Range(range, in: text) else { return nil }
            groups.append(String(text[swiftRange]))
        }
        return groups
    }

    private static func nsRange(_ text: String) -> NSRange {
        NSRange(text.startIndex..., in: text)
    }

    private static func compile(_ pattern: String) -> NSRegularExpression? {
        RegexBox.shared.regex(pattern)
    }
}

// MARK: - Specs

private protocol PhraseSpec {
    var phrase: String { get }
}

private struct Hit<Spec> {
    var spec: Spec
    var range: Range<String.Index>
}

private enum MemoryLanguage {
    case fr, en, es
}

private enum Captured {
    case name(String)
    case description(String)
}

private enum PreferenceKind {
    case prefer, dislike, allergy, avoid
}

private struct NamePhrase: PhraseSpec {
    let phrase: String
    let language: MemoryLanguage
}

private struct GenderPhrase: PhraseSpec {
    let phrase: String
    let language: MemoryLanguage
    let code: String
}

private struct RelationPhrase: PhraseSpec {
    let phrase: String
    let key: String
    let language: MemoryLanguage
    let subject: String
}

private struct PetPhrase: PhraseSpec {
    let phrase: String
    let key: String
    let language: MemoryLanguage
    let subject: String
    let exists: String
    let allowsBare: Bool
}

private struct HomePhrase: PhraseSpec {
    let phrase: String
    let render: (String) -> String
}

private struct TemplatePhrase: PhraseSpec {
    let phrase: String
    let render: (String) -> String
}

private struct LanguagePhrase: PhraseSpec {
    let phrase: String
    let language: MemoryLanguage
}

private struct PreferencePhrase: PhraseSpec {
    let phrase: String
    let kind: PreferenceKind
    let language: MemoryLanguage
}

private struct LanguageName {
    let code: String
    let display: String
}

private final class RegexBox: @unchecked Sendable {
    static let shared = RegexBox()
    private let lock = NSLock()
    private var cache: [String: NSRegularExpression] = [:]

    func regex(_ pattern: String) -> NSRegularExpression? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = cache[pattern] { return cached }
        guard let compiled = try? NSRegularExpression(pattern: pattern) else { return nil }
        cache[pattern] = compiled
        return compiled
    }
}

private let namePhrases: [NamePhrase] = [
    NamePhrase(phrase: "je m'appelle", language: .fr),
    NamePhrase(phrase: "je m appelle", language: .fr),
    NamePhrase(phrase: "mon nom est", language: .fr),
    NamePhrase(phrase: "on m'appelle", language: .fr),
    NamePhrase(phrase: "moi c'est", language: .fr),
    NamePhrase(phrase: "my name is", language: .en),
    NamePhrase(phrase: "my name's", language: .en),
    NamePhrase(phrase: "i am called", language: .en),
    NamePhrase(phrase: "i'm called", language: .en),
    NamePhrase(phrase: "im called", language: .en),
    NamePhrase(phrase: "call me", language: .en),
    NamePhrase(phrase: "me llamo", language: .es),
    NamePhrase(phrase: "mi nombre es", language: .es),
    NamePhrase(phrase: "me llaman", language: .es),
]

private let genderPhrases: [GenderPhrase] = [
    GenderPhrase(phrase: "je suis un homme", language: .fr, code: "man"),
    GenderPhrase(phrase: "je suis une femme", language: .fr, code: "woman"),
    GenderPhrase(phrase: "je suis non-binaire", language: .fr, code: "nonbinary"),
    GenderPhrase(phrase: "je suis non binaire", language: .fr, code: "nonbinary"),
    GenderPhrase(phrase: "i am a man", language: .en, code: "man"),
    GenderPhrase(phrase: "i am a woman", language: .en, code: "woman"),
    GenderPhrase(phrase: "i'm a man", language: .en, code: "man"),
    GenderPhrase(phrase: "i'm a woman", language: .en, code: "woman"),
    GenderPhrase(phrase: "i am male", language: .en, code: "man"),
    GenderPhrase(phrase: "i am female", language: .en, code: "woman"),
    GenderPhrase(phrase: "i'm male", language: .en, code: "man"),
    GenderPhrase(phrase: "i'm female", language: .en, code: "woman"),
    GenderPhrase(phrase: "i am non-binary", language: .en, code: "nonbinary"),
    GenderPhrase(phrase: "i am nonbinary", language: .en, code: "nonbinary"),
    GenderPhrase(phrase: "i'm non-binary", language: .en, code: "nonbinary"),
    GenderPhrase(phrase: "i'm nonbinary", language: .en, code: "nonbinary"),
    GenderPhrase(phrase: "soy un hombre", language: .es, code: "man"),
    GenderPhrase(phrase: "soy una mujer", language: .es, code: "woman"),
    GenderPhrase(phrase: "soy hombre", language: .es, code: "man"),
    GenderPhrase(phrase: "soy mujer", language: .es, code: "woman"),
    GenderPhrase(phrase: "soy no binario", language: .es, code: "nonbinary"),
    GenderPhrase(phrase: "soy no binaria", language: .es, code: "nonbinary"),
]

private let relations: [RelationPhrase] = [
    RelationPhrase(phrase: "my wife", key: "person.wife", language: .en, subject: "The user's wife"),
    RelationPhrase(phrase: "my husband", key: "person.husband", language: .en, subject: "The user's husband"),
    RelationPhrase(phrase: "my girlfriend", key: "person.girlfriend", language: .en, subject: "The user's girlfriend"),
    RelationPhrase(phrase: "my boyfriend", key: "person.boyfriend", language: .en, subject: "The user's boyfriend"),
    RelationPhrase(phrase: "my partner", key: "person.partner", language: .en, subject: "The user's partner"),
    RelationPhrase(phrase: "my daughter", key: "person.daughter", language: .en, subject: "The user's daughter"),
    RelationPhrase(phrase: "my son", key: "person.son", language: .en, subject: "The user's son"),
    RelationPhrase(phrase: "my child", key: "person.child", language: .en, subject: "The user's child"),
    RelationPhrase(phrase: "my children", key: "person.children", language: .en, subject: "The user's children"),
    RelationPhrase(phrase: "my kids", key: "person.children", language: .en, subject: "The user's children"),
    RelationPhrase(phrase: "my mother", key: "person.mother", language: .en, subject: "The user's mother"),
    RelationPhrase(phrase: "my mom", key: "person.mother", language: .en, subject: "The user's mother"),
    RelationPhrase(phrase: "my mum", key: "person.mother", language: .en, subject: "The user's mother"),
    RelationPhrase(phrase: "my father", key: "person.father", language: .en, subject: "The user's father"),
    RelationPhrase(phrase: "my dad", key: "person.father", language: .en, subject: "The user's father"),
    RelationPhrase(phrase: "my brother", key: "person.brother", language: .en, subject: "The user's brother"),
    RelationPhrase(phrase: "my sister", key: "person.sister", language: .en, subject: "The user's sister"),
    RelationPhrase(phrase: "my friend", key: "person.friend", language: .en, subject: "The user's friend"),
    RelationPhrase(phrase: "ma petite amie", key: "person.girlfriend", language: .fr, subject: "La petite amie de l'utilisateur"),
    RelationPhrase(phrase: "mon petit ami", key: "person.boyfriend", language: .fr, subject: "Le petit ami de l'utilisateur"),
    RelationPhrase(phrase: "ma meilleure amie", key: "person.friend", language: .fr, subject: "La meilleure amie de l'utilisateur"),
    RelationPhrase(phrase: "ma femme", key: "person.wife", language: .fr, subject: "La femme de l'utilisateur"),
    RelationPhrase(phrase: "mon épouse", key: "person.wife", language: .fr, subject: "L'épouse de l'utilisateur"),
    RelationPhrase(phrase: "mon epouse", key: "person.wife", language: .fr, subject: "L'épouse de l'utilisateur"),
    RelationPhrase(phrase: "mon mari", key: "person.husband", language: .fr, subject: "Le mari de l'utilisateur"),
    RelationPhrase(phrase: "mon époux", key: "person.husband", language: .fr, subject: "L'époux de l'utilisateur"),
    RelationPhrase(phrase: "ma copine", key: "person.girlfriend", language: .fr, subject: "La copine de l'utilisateur"),
    RelationPhrase(phrase: "mon copain", key: "person.boyfriend", language: .fr, subject: "Le copain de l'utilisateur"),
    RelationPhrase(phrase: "mon partenaire", key: "person.partner", language: .fr, subject: "Le partenaire de l'utilisateur"),
    RelationPhrase(phrase: "ma partenaire", key: "person.partner", language: .fr, subject: "La partenaire de l'utilisateur"),
    RelationPhrase(phrase: "mon fils", key: "person.son", language: .fr, subject: "Le fils de l'utilisateur"),
    RelationPhrase(phrase: "ma fille", key: "person.daughter", language: .fr, subject: "La fille de l'utilisateur"),
    RelationPhrase(phrase: "mes enfants", key: "person.children", language: .fr, subject: "Les enfants de l'utilisateur"),
    RelationPhrase(phrase: "ma mère", key: "person.mother", language: .fr, subject: "La mère de l'utilisateur"),
    RelationPhrase(phrase: "ma mere", key: "person.mother", language: .fr, subject: "La mère de l'utilisateur"),
    RelationPhrase(phrase: "mon père", key: "person.father", language: .fr, subject: "Le père de l'utilisateur"),
    RelationPhrase(phrase: "mon pere", key: "person.father", language: .fr, subject: "Le père de l'utilisateur"),
    RelationPhrase(phrase: "mon frère", key: "person.brother", language: .fr, subject: "Le frère de l'utilisateur"),
    RelationPhrase(phrase: "mon frere", key: "person.brother", language: .fr, subject: "Le frère de l'utilisateur"),
    RelationPhrase(phrase: "ma sœur", key: "person.sister", language: .fr, subject: "La sœur de l'utilisateur"),
    RelationPhrase(phrase: "ma soeur", key: "person.sister", language: .fr, subject: "La sœur de l'utilisateur"),
    RelationPhrase(phrase: "mon amie", key: "person.friend", language: .fr, subject: "L'amie de l'utilisateur"),
    RelationPhrase(phrase: "mon ami", key: "person.friend", language: .fr, subject: "L'ami de l'utilisateur"),
    RelationPhrase(phrase: "mi esposa", key: "person.wife", language: .es, subject: "La esposa del usuario"),
    RelationPhrase(phrase: "mi mujer", key: "person.wife", language: .es, subject: "La mujer del usuario"),
    RelationPhrase(phrase: "mi esposo", key: "person.husband", language: .es, subject: "El esposo del usuario"),
    RelationPhrase(phrase: "mi marido", key: "person.husband", language: .es, subject: "El marido del usuario"),
    RelationPhrase(phrase: "mi novia", key: "person.girlfriend", language: .es, subject: "La novia del usuario"),
    RelationPhrase(phrase: "mi novio", key: "person.boyfriend", language: .es, subject: "El novio del usuario"),
    RelationPhrase(phrase: "mi pareja", key: "person.partner", language: .es, subject: "La pareja del usuario"),
    RelationPhrase(phrase: "mi hija", key: "person.daughter", language: .es, subject: "La hija del usuario"),
    RelationPhrase(phrase: "mi hijo", key: "person.son", language: .es, subject: "El hijo del usuario"),
    RelationPhrase(phrase: "mi madre", key: "person.mother", language: .es, subject: "La madre del usuario"),
    RelationPhrase(phrase: "mi mamá", key: "person.mother", language: .es, subject: "La madre del usuario"),
    RelationPhrase(phrase: "mi mama", key: "person.mother", language: .es, subject: "La madre del usuario"),
    RelationPhrase(phrase: "mi padre", key: "person.father", language: .es, subject: "El padre del usuario"),
    RelationPhrase(phrase: "mi papá", key: "person.father", language: .es, subject: "El padre del usuario"),
    RelationPhrase(phrase: "mi papa", key: "person.father", language: .es, subject: "El padre del usuario"),
    RelationPhrase(phrase: "mi hermano", key: "person.brother", language: .es, subject: "El hermano del usuario"),
    RelationPhrase(phrase: "mi hermana", key: "person.sister", language: .es, subject: "La hermana del usuario"),
    RelationPhrase(phrase: "mi amiga", key: "person.friend", language: .es, subject: "La amiga del usuario"),
    RelationPhrase(phrase: "mi amigo", key: "person.friend", language: .es, subject: "El amigo del usuario"),
]

private let pets: [PetPhrase] = [
    PetPhrase(phrase: "i have a dog", key: "pet.dog", language: .en, subject: "The user's dog", exists: "The user has a dog.", allowsBare: true),
    PetPhrase(phrase: "i have a cat", key: "pet.cat", language: .en, subject: "The user's cat", exists: "The user has a cat.", allowsBare: true),
    PetPhrase(phrase: "my dog", key: "pet.dog", language: .en, subject: "The user's dog", exists: "The user has a dog.", allowsBare: false),
    PetPhrase(phrase: "my cat", key: "pet.cat", language: .en, subject: "The user's cat", exists: "The user has a cat.", allowsBare: false),
    PetPhrase(phrase: "my bird", key: "pet.bird", language: .en, subject: "The user's bird", exists: "The user has a bird.", allowsBare: false),
    PetPhrase(phrase: "my rabbit", key: "pet.rabbit", language: .en, subject: "The user's rabbit", exists: "The user has a rabbit.", allowsBare: false),
    PetPhrase(phrase: "my fish", key: "pet.fish", language: .en, subject: "The user's fish", exists: "The user has a fish.", allowsBare: false),
    PetPhrase(phrase: "my pet", key: "pet.pet", language: .en, subject: "The user's pet", exists: "The user has a pet.", allowsBare: false),
    PetPhrase(phrase: "j'ai un chien", key: "pet.dog", language: .fr, subject: "Le chien de l'utilisateur", exists: "L'utilisateur a un chien.", allowsBare: true),
    PetPhrase(phrase: "j'ai une chienne", key: "pet.dog", language: .fr, subject: "La chienne de l'utilisateur", exists: "L'utilisateur a une chienne.", allowsBare: true),
    PetPhrase(phrase: "j'ai un chat", key: "pet.cat", language: .fr, subject: "Le chat de l'utilisateur", exists: "L'utilisateur a un chat.", allowsBare: true),
    PetPhrase(phrase: "mon chien", key: "pet.dog", language: .fr, subject: "Le chien de l'utilisateur", exists: "L'utilisateur a un chien.", allowsBare: false),
    PetPhrase(phrase: "ma chienne", key: "pet.dog", language: .fr, subject: "La chienne de l'utilisateur", exists: "L'utilisateur a une chienne.", allowsBare: false),
    PetPhrase(phrase: "mon chat", key: "pet.cat", language: .fr, subject: "Le chat de l'utilisateur", exists: "L'utilisateur a un chat.", allowsBare: false),
    PetPhrase(phrase: "ma chatte", key: "pet.cat", language: .fr, subject: "La chatte de l'utilisateur", exists: "L'utilisateur a une chatte.", allowsBare: false),
    PetPhrase(phrase: "mon oiseau", key: "pet.bird", language: .fr, subject: "L'oiseau de l'utilisateur", exists: "L'utilisateur a un oiseau.", allowsBare: false),
    PetPhrase(phrase: "mon lapin", key: "pet.rabbit", language: .fr, subject: "Le lapin de l'utilisateur", exists: "L'utilisateur a un lapin.", allowsBare: false),
    PetPhrase(phrase: "tengo un perro", key: "pet.dog", language: .es, subject: "El perro del usuario", exists: "El usuario tiene un perro.", allowsBare: true),
    PetPhrase(phrase: "tengo un gato", key: "pet.cat", language: .es, subject: "El gato del usuario", exists: "El usuario tiene un gato.", allowsBare: true),
    PetPhrase(phrase: "mi perro", key: "pet.dog", language: .es, subject: "El perro del usuario", exists: "El usuario tiene un perro.", allowsBare: false),
    PetPhrase(phrase: "mi perra", key: "pet.dog", language: .es, subject: "La perra del usuario", exists: "El usuario tiene una perra.", allowsBare: false),
    PetPhrase(phrase: "mi gato", key: "pet.cat", language: .es, subject: "El gato del usuario", exists: "El usuario tiene un gato.", allowsBare: false),
    PetPhrase(phrase: "mi gata", key: "pet.cat", language: .es, subject: "La gata del usuario", exists: "El usuario tiene una gata.", allowsBare: false),
    PetPhrase(phrase: "mi mascota", key: "pet.pet", language: .es, subject: "La mascota del usuario", exists: "El usuario tiene una mascota.", allowsBare: false),
]

private let homes: [HomePhrase] = [
    HomePhrase(phrase: "j'habite à", render: { "L'utilisateur habite à \($0)." }),
    HomePhrase(phrase: "j'habite a", render: { "L'utilisateur habite à \($0)." }),
    HomePhrase(phrase: "j'habite en", render: { "L'utilisateur habite en \($0)." }),
    HomePhrase(phrase: "j'habite au", render: { "L'utilisateur habite au \($0)." }),
    HomePhrase(phrase: "j'habite aux", render: { "L'utilisateur habite aux \($0)." }),
    HomePhrase(phrase: "j'habite dans", render: { "L'utilisateur habite dans \($0)." }),
    HomePhrase(phrase: "je vis à", render: { "L'utilisateur vit à \($0)." }),
    HomePhrase(phrase: "je vis a", render: { "L'utilisateur vit à \($0)." }),
    HomePhrase(phrase: "je vis en", render: { "L'utilisateur vit en \($0)." }),
    HomePhrase(phrase: "i live in", render: { "The user lives in \($0)." }),
    HomePhrase(phrase: "i live at", render: { "The user lives at \($0)." }),
    HomePhrase(phrase: "i live on", render: { "The user lives on \($0)." }),
    HomePhrase(phrase: "vivo en", render: { "El usuario vive en \($0)." }),
]

private let jobs: [TemplatePhrase] = [
    TemplatePhrase(phrase: "je travaille en tant que", render: { "L'utilisateur travaille comme \($0)." }),
    TemplatePhrase(phrase: "je travaille comme", render: { "L'utilisateur travaille comme \($0)." }),
    TemplatePhrase(phrase: "mon métier est", render: { "Le métier de l'utilisateur est \($0)." }),
    TemplatePhrase(phrase: "mon metier est", render: { "Le métier de l'utilisateur est \($0)." }),
    TemplatePhrase(phrase: "i work as", render: { "The user works as \($0)." }),
    TemplatePhrase(phrase: "my job is", render: { "The user's job is \($0)." }),
    TemplatePhrase(phrase: "trabajo como", render: { "El usuario trabaja como \($0)." }),
    TemplatePhrase(phrase: "mi trabajo es", render: { "El trabajo del usuario es \($0)." }),
]

private let projects: [TemplatePhrase] = [
    TemplatePhrase(phrase: "je travaille sur", render: { "L'utilisateur travaille sur \($0)." }),
    TemplatePhrase(phrase: "mon projet s'appelle", render: { "Le projet de l'utilisateur s'appelle \($0)." }),
    TemplatePhrase(phrase: "mon projet est", render: { "Le projet de l'utilisateur est \($0)." }),
    TemplatePhrase(phrase: "i am working on", render: { "The user is working on \($0)." }),
    TemplatePhrase(phrase: "i'm working on", render: { "The user is working on \($0)." }),
    TemplatePhrase(phrase: "im working on", render: { "The user is working on \($0)." }),
    TemplatePhrase(phrase: "i work on", render: { "The user is working on \($0)." }),
    TemplatePhrase(phrase: "my project is", render: { "The user's project is \($0)." }),
    TemplatePhrase(phrase: "estoy trabajando en", render: { "El usuario está trabajando en \($0)." }),
    TemplatePhrase(phrase: "mi proyecto es", render: { "El proyecto del usuario es \($0)." }),
]

private let languagePhrases: [LanguagePhrase] = [
    LanguagePhrase(phrase: "je parle", language: .fr),
    LanguagePhrase(phrase: "ma langue est", language: .fr),
    LanguagePhrase(phrase: "i speak", language: .en),
    LanguagePhrase(phrase: "my language is", language: .en),
    LanguagePhrase(phrase: "hablo", language: .es),
    LanguagePhrase(phrase: "mi idioma es", language: .es),
]

private let preferences: [PreferencePhrase] = [
    PreferencePhrase(phrase: "je suis allergique aux", kind: .allergy, language: .fr),
    PreferencePhrase(phrase: "je suis allergique au", kind: .allergy, language: .fr),
    PreferencePhrase(phrase: "je suis allergique à", kind: .allergy, language: .fr),
    PreferencePhrase(phrase: "je suis allergique a", kind: .allergy, language: .fr),
    PreferencePhrase(phrase: "i am allergic to", kind: .allergy, language: .en),
    PreferencePhrase(phrase: "i'm allergic to", kind: .allergy, language: .en),
    PreferencePhrase(phrase: "soy alérgica a", kind: .allergy, language: .es),
    PreferencePhrase(phrase: "soy alergica a", kind: .allergy, language: .es),
    PreferencePhrase(phrase: "soy alérgico a", kind: .allergy, language: .es),
    PreferencePhrase(phrase: "soy alergico a", kind: .allergy, language: .es),
    PreferencePhrase(phrase: "je n'aime pas", kind: .dislike, language: .fr),
    PreferencePhrase(phrase: "je déteste", kind: .dislike, language: .fr),
    PreferencePhrase(phrase: "je deteste", kind: .dislike, language: .fr),
    PreferencePhrase(phrase: "i do not like", kind: .dislike, language: .en),
    PreferencePhrase(phrase: "i don't like", kind: .dislike, language: .en),
    PreferencePhrase(phrase: "i hate", kind: .dislike, language: .en),
    PreferencePhrase(phrase: "no me gusta", kind: .dislike, language: .es),
    PreferencePhrase(phrase: "odio", kind: .dislike, language: .es),
    PreferencePhrase(phrase: "je ne mange pas de", kind: .avoid, language: .fr),
    PreferencePhrase(phrase: "je ne mange pas", kind: .avoid, language: .fr),
    PreferencePhrase(phrase: "j'évite", kind: .avoid, language: .fr),
    PreferencePhrase(phrase: "j'evite", kind: .avoid, language: .fr),
    PreferencePhrase(phrase: "i do not eat", kind: .avoid, language: .en),
    PreferencePhrase(phrase: "i don't eat", kind: .avoid, language: .en),
    PreferencePhrase(phrase: "i avoid", kind: .avoid, language: .en),
    PreferencePhrase(phrase: "no como", kind: .avoid, language: .es),
    PreferencePhrase(phrase: "evito", kind: .avoid, language: .es),
    PreferencePhrase(phrase: "je préfère", kind: .prefer, language: .fr),
    PreferencePhrase(phrase: "je prefere", kind: .prefer, language: .fr),
    PreferencePhrase(phrase: "i prefer", kind: .prefer, language: .en),
    PreferencePhrase(phrase: "prefiero", kind: .prefer, language: .es),
]

private let languageNames: [String: LanguageName] = {
    var map: [String: LanguageName] = [:]
    let rows: [(String, String, String)] = [
        ("french", "fr", "French"), ("français", "fr", "français"), ("francais", "fr", "français"),
        ("english", "en", "English"), ("anglais", "en", "anglais"), ("inglés", "en", "inglés"), ("ingles", "en", "inglés"),
        ("spanish", "es", "Spanish"), ("espagnol", "es", "espagnol"), ("español", "es", "español"), ("espanol", "es", "español"),
        ("german", "de", "German"), ("allemand", "de", "allemand"), ("alemán", "de", "alemán"), ("aleman", "de", "alemán"),
        ("italian", "it", "Italian"), ("italien", "it", "italien"), ("italiano", "it", "italiano"),
        ("portuguese", "pt", "Portuguese"), ("portugais", "pt", "portugais"), ("portugués", "pt", "portugués"), ("portugues", "pt", "portugués"),
        ("arabic", "ar", "Arabic"), ("arabe", "ar", "arabe"), ("árabe", "ar", "árabe"),
        ("chinese", "zh", "Chinese"), ("chinois", "zh", "chinois"), ("chino", "zh", "chino"),
        ("japanese", "ja", "Japanese"), ("japonais", "ja", "japonais"), ("japonés", "ja", "japonés"), ("japones", "ja", "japonés"),
        ("korean", "ko", "Korean"), ("coréen", "ko", "coréen"), ("coreen", "ko", "coréen"), ("coreano", "ko", "coreano"),
        ("russian", "ru", "Russian"), ("russe", "ru", "russe"), ("ruso", "ru", "ruso"),
        ("dutch", "nl", "Dutch"), ("néerlandais", "nl", "néerlandais"), ("neerlandais", "nl", "néerlandais"),
        ("turkish", "tr", "Turkish"), ("turc", "tr", "turc"), ("turco", "tr", "turco"),
        ("polish", "pl", "Polish"), ("polonais", "pl", "polonais"), ("polaco", "pl", "polaco"),
        ("greek", "el", "Greek"), ("grec", "el", "grec"), ("griego", "el", "griego"),
        ("hebrew", "he", "Hebrew"), ("hébreu", "he", "hébreu"), ("hebreu", "he", "hébreu"),
        ("hindi", "hi", "Hindi"),
        ("catalan", "ca", "Catalan"), ("català", "ca", "català"), ("catalan", "ca", "catalan"),
    ]
    for (token, code, display) in rows {
        map[token] = LanguageName(code: code, display: display)
    }
    return map
}()

private let languageSkip: Set<String> = [
    "le", "la", "les", "the", "el", "los", "las", "un", "une", "a", "an",
    "peu", "poco", "little", "bit", "couramment", "fluently", "bien", "well",
    "seulement", "only", "aussi", "too", "très", "tres", "very", "uniquement",
]

private let conjunctions: Set<String> = [
    "et", "and", "y", "ou", "or", "pero", "mais", "but", "puis", "then",
]

private let negationTokens: Set<String> = [
    "not", "no", "pas", "ne", "n", "nunca", "jamais", "non", "neither", "nor", "sans", "without",
]

private let nameStopwords: Set<String> = [
    "comment", "quoi", "qui", "que", "how", "what", "who", "why", "where", "when",
    "pourquoi", "où", "ou", "cómo", "como", "dónde", "donde", "qué",
    "the", "a", "an", "un", "une", "le", "la", "les", "el", "los", "las",
    "je", "tu", "il", "elle", "on", "nous", "vous", "i", "you", "he", "she", "we", "they",
    "me", "moi", "toi", "please", "stp", "fatigué", "fatigue", "tired", "fine", "bien", "mal",
    "là", "here", "ready", "ok", "okay", "oui", "non", "yes", "no", "si", "vrai", "faux",
    "content", "happy", "sad", "triste", "good", "bad", "great", "super", "ça", "ca", "cela",
    "this", "that", "it", "just", "seulement", "aussi", "too", "very", "très", "tres",
    "later", "tomorrow", "back", "soon", "maybe", "maintenant", "aujourd", "aujourd'hui",
    "not", "pas", "rien", "nothing", "someone", "quelqu", "quelqu'un",
]

private let vagueObjects: Set<String> = [
    "that", "this", "it", "them", "those", "these", "ça", "ca", "cela", "ceci",
    "eso", "esto", "esa", "lui", "elle", "moi", "toi", "you", "me", "him", "her",
    "something", "anything", "nothing", "rien", "tout", "todo", "nada", "so",
    "très", "tres", "mucho", "beaucoup", "ici", "here", "there", "là",
]

private let jobArticles: Set<String> = [
    "a", "an", "the", "un", "une", "le", "la", "les", "el", "los", "las", "des", "du",
]

private let jobChatter: Set<String> = [
    "intéressant", "interessant", "bien", "bon", "bonne", "fini", "finie", "done",
    "good", "great", "hard", "difficile", "cool", "ok", "okay", "nul", "nulle",
    "boring", "ennuyeux", "beaucoup", "trop", "fine", "amazing", "awesome",
    "terrible", "mal", "bad", "super", "génial", "genial", "it", "that", "this", "ça",
]

private let placeParticles: Set<String> = [
    "de", "du", "des", "la", "le", "les", "et", "of", "the", "del",
]

private let placeChatter: Set<String> = [
    "ici", "here", "there", "là", "la", "somewhere", "partout", "nowhere",
]
