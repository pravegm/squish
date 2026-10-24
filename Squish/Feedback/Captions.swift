import Foundation

/// Visual onomatopoeia for captions and VoiceOver (02 §6 accessibility). Comic-book words, one per meaningful moment;
/// grains, contact and the hush are never captioned. `announce` is true only for the big moments:
/// the failure, the ka-chunk and the reveal.
enum Captions {
    static func caption(for event: PressEvent, context: FeedbackContext) -> (text: String, announce: Bool)? {
        switch event {
        case .armed, .contact, .grain, .hush, .bottomOut, .sealed, .released:
            return nil
        case .preFailureTell:
            guard let text = tell(context.kind) else { return nil }
            return (text: text, announce: false)
        case .fracture(let index, let isFailure):
            if isFailure {
                return (text: failure(context.kind), announce: true)
            }
            guard let text = fracture(context.kind, index: index) else { return nil }
            return (text: text, announce: false)
        case .kaChunk:
            return (text: "KA-CHUNK", announce: true)
        case .reveal:
            return (text: reveal(context), announce: true)
        }
    }

    /// The word for an object's big failure.
    static func failure(_ kind: ObjectKind) -> String {
        switch kind {
        case .bubbleWrap: "POP!"
        case .rubberDuck: "POP! BLOOP!"
        case .jelly: "SPLAT!"
        case .crayon: "SNAP!"
        case .egg: "CRACK!"
        case .cakeSlice: "SQUISH!"
        case .sodaCan: "FSSSHT!"
        case .gummyBear: "SPLIT!"
        case .glassBottle: "SMASH!"
        case .unsquishable: "CLANG… CRACK?!"
        }
    }

    /// Words for the smaller fractures (indices in ascending compression order, see `MaterialProfile`).
    static func fracture(_ kind: ObjectKind, index: Int) -> String? {
        switch kind {
        case .bubbleWrap:
            let words = ["POP!", "POP!", "PIP!", "POP!", "PAP!"]
            return words[abs(index) % words.count]
        case .rubberDuck:
            return "HONK!"
        case .jelly:
            return "SHLIP!"
        case .crayon:
            // The Crayon Box: a SNAP! per crayon, then the crumble (the last fracture).
            return index >= CrayonRecipe.crumbleIndex ? "crumble…" : "SNAP!"
        case .egg:
            return index == 0 ? "tik!" : "SPLAT!"
        case .cakeSlice:
            return index == 0 ? "crunch!" : "BWOING!"
        case .sodaCan:
            return index > 2 ? "CRUNCH!" : "CRNK!"
        case .gummyBear:
            return "SQUISH!"
        case .glassBottle:
            return index == 0 ? "CRACK!" : "crunch!"
        case .unsquishable:
            return index == 0 ? "CLANG…" : "GROAN…"
        }
    }

    /// The build-up before the failure (not announced).
    static func tell(_ kind: ObjectKind) -> String? {
        switch kind {
        case .glassBottle: "tik… tik…"
        case .egg: "tik…"
        case .crayon: "creak…"
        case .sodaCan: "crnk…"
        case .rubberDuck: "squeeeak…"
        case .unsquishable: "GROOOAN…"
        case .bubbleWrap, .jelly, .cakeSlice, .gummyBear: nil
        }
    }

    static func reveal(_ context: FeedbackContext) -> String {
        if context.kind == .unsquishable { return "PRESS 0 – BALL 1" }
        if context.variant.isGolden { return "GOLDEN!" }
        if let surprise = context.variant.surprise { return "\(surprise.title)!" }
        // Only ever heard (VoiceOver); the reveal card itself carries the visuals.
        return "Done. Here's what's left."
    }
}
