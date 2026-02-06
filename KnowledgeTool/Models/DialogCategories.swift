import Foundation

// MARK: - Predefined Dialog Categories

/// Static definitions for all dialog categories
enum DialogCategories {

    /// All available dialog categories for character dialog examples
    static let all: [DialogCategory] = [
        // GREETINGS (~5 examples)
        DialogCategory(
            id: "greetings",
            name: "Greetings",
            description: "How the character greets someone at the start of a conversation",
            suggestedCount: 5,
            contextPrompt: """
            Generate greeting lines this character would say when someone approaches them or starts a conversation.
            Show their personality through their welcome style. These should feel natural and authentic to how
            the character typically greets people.
            """
        ),

        // GOODBYES (~1 example)
        DialogCategory(
            id: "goodbyes",
            name: "Goodbyes",
            description: "How the character says farewell",
            suggestedCount: 1,
            contextPrompt: """
            Generate farewell lines this character would say when a conversation ends.
            Capture their personality in how they part ways - whether warm, casual, formal, or unique to their style.
            """
        ),

        // MODERATION REDIRECTS (~10 examples)
        DialogCategory(
            id: "moderation_redirects",
            name: "Moderation Redirects",
            description: "How the character deflects when asked about topics they cannot discuss",
            suggestedCount: 10,
            contextPrompt: """
            Generate responses for when someone asks the character about inappropriate, dangerous, or off-limits topics.
            The character should redirect without breaking character - showing discomfort, deflection, or refusal in their
            unique voice. These are critical for keeping the character in-bounds while staying authentic.
            """
        ),

        // APOLOGIES (~5 examples)
        DialogCategory(
            id: "apologies",
            name: "Apologies",
            description: "How the character apologizes (or refuses to)",
            suggestedCount: 5,
            contextPrompt: """
            Generate apology lines (or refusals to apologize) that match this character's personality.
            Some characters apologize gracefully, others deflect, others double down. Show their authentic response
            when they've made a mistake or upset someone.
            """
        ),

        // BOREDOM/IDLE (~2 examples)
        DialogCategory(
            id: "boredom",
            name: "Boredom/Idle",
            description: "What the character says when they haven't been responded to in a while",
            suggestedCount: 2,
            contextPrompt: """
            Generate lines the character would say after a period of silence or no response.
            Show how they handle being ignored or waiting - do they get impatient, make jokes, show concern, or something else?
            """
        ),

        // FOLLOW-UP QUESTIONS (~15 examples)
        DialogCategory(
            id: "follow_up_questions",
            name: "Follow-up Questions",
            description: "Questions the character asks to engage with users and keep conversation going",
            suggestedCount: 15,
            contextPrompt: """
            Generate questions this character would ask to show interest, probe deeper, or keep the conversation engaging.
            Include their curiosity style and how they draw information out of others. These should feel natural
            and reflect the character's interests and personality.
            """
        ),

        // HUMOR/WIT (~10 examples)
        DialogCategory(
            id: "humor",
            name: "Humor & Wit",
            description: "Examples that showcase the character's sense of humor when they think they're being funny",
            suggestedCount: 10,
            contextPrompt: """
            Generate lines where the character is consciously being funny, clever, or witty.
            Show their comedic style - whether it's self-deprecating, observational, sarcastic, punny, or absurd.
            These should capture moments when the character is trying to make someone laugh or smile.
            """
        ),

        // ENCOURAGEMENT (~5 examples)
        DialogCategory(
            id: "encouragement",
            name: "Encouragement",
            description: "How the character offers support or encouragement",
            suggestedCount: 5,
            contextPrompt: """
            Generate supportive or encouraging lines in this character's voice.
            How do they lift someone's spirits or offer comfort? This reveals their empathetic side
            and how they connect with others during difficult moments.
            """
        ),

        // REACTIONS (~5 examples)
        DialogCategory(
            id: "reactions",
            name: "Reactions",
            description: "Short reactions to good news, bad news, surprises",
            suggestedCount: 5,
            contextPrompt: """
            Generate short reactive lines - how does this character respond to surprising, exciting, or disappointing news?
            Capture their emotional expressiveness in brief, punchy responses.
            """
        ),

        // THINKING/PROCESSING (~3 examples)
        DialogCategory(
            id: "thinking",
            name: "Thinking/Processing",
            description: "What the character says when they need a moment to think",
            suggestedCount: 3,
            contextPrompt: """
            Generate lines the character says when processing information or thinking out loud.
            Show their contemplative voice and how they handle moments that require thought or reflection.
            """
        )
    ]

    /// Get a category by its ID
    static func category(for id: String) -> DialogCategory? {
        all.first { $0.id == id }
    }

    /// Get categories by IDs
    static func categories(for ids: [String]) -> [DialogCategory] {
        ids.compactMap { category(for: $0) }
    }

    /// Total suggested examples across all categories
    static var totalSuggestedCount: Int {
        all.reduce(0) { $0 + $1.suggestedCount }
    }

    /// Core categories that should be prioritized for basic character setup
    static var coreCategories: [DialogCategory] {
        categories(for: ["greetings", "moderation_redirects", "follow_up_questions", "humor"])
    }

    /// IDs of core categories
    static var coreCategoryIds: [String] {
        ["greetings", "moderation_redirects", "follow_up_questions", "humor"]
    }
}
