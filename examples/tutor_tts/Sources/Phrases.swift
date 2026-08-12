import Foundation

// --------------------------------------------------------------------------------------
// TutorPhraseBook — demo scripts only (not VoicePacks clone transcripts)
// --------------------------------------------------------------------------------------
/// One stock tutor line: picker title + tagged script for streaming synth.
///
/// Spoken content lives here. ``VoicePacks/tutor_*/voice.json`` only holds
/// clone identity (`ref_text` / codes / embedding) for `set_voice`.
struct TutorPhrase: Identifiable, Hashable {
    let id: String
    let title: String
    /// LLM-style tags the demo parses and streams span-by-span.
    let tagged: String
}

enum TutorPhraseBook {

    // ----------------------------------------------------------------------------------
    // Public Attributes
    // ----------------------------------------------------------------------------------
    /// Mixed-language drills — keep target spans long enough that ICL
    /// padding does not rush or clip the clone (prefer ~one full sentence).
    static let all: [TutorPhrase] = [
        TutorPhrase(
            id: "greet_es",
            title: "Spanish — greetings",
            tagged: """
            <en>Let's practice a natural Spanish greeting. First, how are you:</en>
            <es>Hola, ¿cómo estás hoy? Espero que todo vaya muy bien.</es>
            <en>And a warm thank you:</en>
            <es>Muchas gracias por tu ayuda. Te lo agradezco de verdad.</es>
            """
        ),
        TutorPhrase(
            id: "cafe_es",
            title: "Spanish — at the café",
            tagged: """
            <en>At a café in Madrid, you can order like this:</en>
            <es>Buenos días. Quisiera un café con leche y una medialuna, por favor.</es>
            <en>If something is missing, politely ask:</en>
            <es>Disculpe, ¿me podría traer también un vaso de agua?</es>
            """
        ),
        TutorPhrase(
            id: "hello_fr",
            title: "French — morning chat",
            tagged: """
            <en>In French, start the morning with a full greeting:</en>
            <fr>Bonjour, comment allez-vous ce matin? J'espère que vous avez bien dormi.</fr>
            <en>And when you leave later:</en>
            <fr>À bientôt! Passez une très belle journée et à la prochaine.</fr>
            """
        ),
        TutorPhrase(
            id: "market_fr",
            title: "French — market stall",
            tagged: """
            <en>Buying fruit at a French market sounds like this:</en>
            <fr>Bonjour madame. Je voudrais un kilo de pommes et quelques fraises, s'il vous plaît.</fr>
            <en>Then confirm the price politely:</en>
            <fr>Parfait, merci beaucoup. Je vais payer par carte, si c'est possible.</fr>
            """
        ),
        TutorPhrase(
            id: "please_de",
            title: "German — polite requests",
            tagged: """
            <en>In German, a polite request often sounds like this:</en>
            <de>Entschuldigung, könnten Sie mir bitte helfen? Ich suche den Bahnhof.</de>
            <en>And a short apology if you bump into someone:</en>
            <de>Oh, Entschuldigung! Das war nicht Absicht. Geht es Ihnen gut?</de>
            """
        ),
        TutorPhrase(
            id: "travel_de",
            title: "German — train travel",
            tagged: """
            <en>Asking for directions at a German station:</en>
            <de>Guten Tag. Können Sie mir bitte sagen, von welchem Gleis der Zug nach München fährt?</de>
            <en>And thank the person afterward:</en>
            <de>Vielen Dank für Ihre Hilfe. Das war wirklich sehr freundlich von Ihnen.</de>
            """
        ),
        TutorPhrase(
            id: "how_pt",
            title: "Portuguese — catch up",
            tagged: """
            <en>In Portuguese, check in with a friend like this:</en>
            <pt>Oi! Como vai você hoje? Faz tempo que a gente não se fala.</pt>
            <en>Suggest meeting later:</en>
            <pt>Que tal tomarmos um café amanhã à tarde, se você estiver livre?</pt>
            """
        ),
    ]

    static let lesson: TutorPhrase = TutorPhrase(
        id: "full_lesson",
        title: "Full mini-lesson (all languages)",
        tagged: """
        <en>Welcome — today we will practice a few everyday phrases you can use right away.</en>
        <en>In Spanish, how are you is:</en>
        <es>Hola, ¿cómo estás hoy? Espero que todo vaya muy bien.</es>
        <en>And thank you is:</en>
        <es>Muchas gracias por tu ayuda. Te lo agradezco de verdad.</es>
        <en>In French, good morning is:</en>
        <fr>Bonjour, comment allez-vous ce matin? J'espère que vous avez bien dormi.</fr>
        <en>And see you soon is:</en>
        <fr>À bientôt! Passez une très belle journée et à la prochaine.</fr>
        <en>In German, please is:</en>
        <de>Entschuldigung, könnten Sie mir bitte helfen? Ich suche den Bahnhof.</de>
        <en>And excuse me is:</en>
        <de>Oh, Entschuldigung! Das war nicht Absicht. Geht es Ihnen gut?</de>
        <en>In Portuguese, how are you is:</en>
        <pt>Oi! Como vai você hoje? Faz tempo que a gente não se fala.</pt>
        <en>Try repeating each phrase after me, then use it in a real conversation.</en>
        """
    )
}
