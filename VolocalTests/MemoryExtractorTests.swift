import XCTest
@testable import Volocal

final class MemoryExtractorTests: XCTestCase {
    func testNamesInFrenchEnglishAndSpanish() {
        assertMemory("je m'appelle Camille", key: "name", category: "name", contains: "Camille")
        assertMemory("Je m'appelle ada lovelace", key: "name", category: "name", contains: "Ada Lovelace")
        assertMemory("je m\u{2019}appelle Léa", key: "name", category: "name", contains: "Léa")
        assertMemory("my name is Ada", key: "name", category: "name", contains: "Ada")
        assertMemory("my name's Grace Hopper", key: "name", category: "name", contains: "Grace Hopper")
        assertMemory("me llamo Lucía", key: "name", category: "name", contains: "Lucía")
        assertMemory("mi nombre es Juan Carlos", key: "name", category: "name", contains: "Juan Carlos")
    }

    func testClosePeoplePetsHomeAndJob() {
        assertMemory("ma femme Léa", key: "person.wife", category: "person", contains: "Léa")
        assertMemory("my wife is Claire", key: "person.wife", category: "person", contains: "Claire")
        assertMemory("mi esposa se llama Ana", key: "person.wife", category: "person", contains: "Ana")
        assertMemory("my dog Rex", key: "pet.dog", category: "pet", contains: "Rex")
        assertMemory("mon chien s'appelle Max", key: "pet.dog", category: "pet", contains: "Max")
        assertMemory("j'habite à Lyon", key: "home", category: "home", contains: "Lyon")
        assertMemory("I live in San Francisco", key: "home", category: "home", contains: "San Francisco")
        assertMemory("vivo en Madrid", key: "home", category: "home", contains: "Madrid")
        assertMemory("je travaille comme ingénieur", key: "job", category: "job", contains: "ingénieur")
        assertMemory("I work as a nurse", key: "job", category: "job", contains: "nurse")
        assertMemory("trabajo como médica", key: "job", category: "job", contains: "médica")
    }

    func testLanguageProjectPreferenceAgeAndGenderOnlyWhenStated() {
        assertMemory("je parle français", key: "language.fr", category: "language", contains: "français")
        assertMemory("I speak English and Spanish", key: "language.en+es", category: "language", contains: "English")
        assertMemory("je travaille sur Volocal", key: "project.volocal", category: "project", contains: "Volocal")
        assertMemory("I prefer short answers", key: "preference.short-answers", category: "preference", contains: "short answers")
        assertMemory("je n'aime pas le froid", key: "limit.froid", category: "limit", contains: "froid")
        assertMemory("j'ai 32 ans", key: "age", category: "age", contains: "32")
        assertMemory("I am 41 years old", key: "age", category: "age", contains: "41")
        assertMemory("tengo 5 años", key: "age", category: "age", contains: "5")
        assertMemory("je suis un homme", key: "gender", category: "gender", contains: "homme")
        assertMemory("I am a woman", key: "gender", category: "gender", contains: "woman")
        assertMemory("soy una mujer", key: "gender", category: "gender", contains: "mujer")
    }

    func testOneFactPerTurnAndSameKeyAcrossLanguages() {
        let draft = MemoryExtractor.extract(from: "je m'appelle Marc et j'habite à Lyon")
        XCTAssertEqual(draft?.key, "name")
        XCTAssertFalse(draft?.text.contains("Lyon") == true)

        let english = MemoryExtractor.extract(from: "my wife is Léa")
        let french = MemoryExtractor.extract(from: "ma femme Claire")
        XCTAssertEqual(english?.key, french?.key)
    }

    func testSkipsChitChatNegationAndTheAssistant() {
        let ignored = [
            "salut",
            "bonjour",
            "hello how are you",
            "ça va",
            "merci",
            "oui",
            "je suis fatigué",
            "je suis là",
            "je suis ingénieur",
            "I am happy",
            "I am 32",
            "I am a teacher",
            "tu t'appelles comment",
            "what is your name",
            "you are Volocal",
            "tu es un assistant",
            "your name is Volocal",
            "je parle de mon weekend",
            "I like it",
            "me gusta",
            "my dog",
            "ma femme",
            "j'habite",
            "no me llamo Juan",
            "my name is not John",
            "je ne suis pas un homme",
            "call me later",
        ]
        for utterance in ignored {
            XCTAssertNil(MemoryExtractor.extract(from: utterance), utterance)
        }
    }

    func testSentencesAreOneLineAboutTheUser() {
        let samples = [
            "my name is Ada",
            "je m'appelle Camille",
            "me llamo Lucía",
            "ma femme Léa",
            "my dog Rex",
            "j'habite à Lyon",
            "je travaille comme ingénieur",
            "I have a dog",
            "I'm allergic to peanuts",
        ]
        for sample in samples {
            guard let draft = MemoryExtractor.extract(from: sample) else {
                XCTFail("missing fact for \(sample)")
                continue
            }
            XCTAssertFalse(draft.text.contains("\n"), draft.text)
            XCTAssertTrue(draft.text.hasSuffix("."), draft.text)
            XCTAssertFalse(draft.text.lowercased().contains("volocal"), draft.text)
            let lower = draft.text.lowercased()
            XCTAssertTrue(
                lower.contains("user") || lower.contains("usuario") || lower.contains("utilisateur"),
                draft.text
            )
        }
    }

    private func assertMemory(
        _ utterance: String,
        key: String,
        category: String,
        contains: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let draft = MemoryExtractor.extract(from: utterance)
        XCTAssertNotNil(draft, "expected a fact from: \(utterance)", file: file, line: line)
        XCTAssertEqual(draft?.key, key, utterance, file: file, line: line)
        XCTAssertEqual(draft?.category, category, utterance, file: file, line: line)
        XCTAssertTrue(draft?.text.contains(contains) == true, draft?.text ?? utterance, file: file, line: line)
    }
}
