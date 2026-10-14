import Testing

@testable import loom

@Test func streamingReleasesEarlierTableWhileLaterTableRemainsPending() {
    let first = "| a | b |\n| --- | --- |\n| one | two |"
    let second = "| c | d |\n| --- | --- |\n| three |"
    let source = first + "\n\nafter\n\n" + second
    let snapshot = MarkdownText.streaming(source)
    #expect(snapshot.stableSpans.map(\.text).joined().contains("one"))
    #expect(snapshot.stableSpans.map(\.text).joined().contains("after"))
    #expect(!snapshot.stableSpans.map(\.text).joined().contains("three"))
    #expect(snapshot.pendingSpans.map(\.text).joined().contains("three"))
    #expect(!snapshot.requiresFinalReflow)
    #expect(snapshot.spans.map(\.text) == MarkdownText.spans(source).map(\.text))
}

@Test func streamingKeepsContainingQuoteMutable() {
    let source = "> | a | b |\n> | --- | --- |\n> | one | two |\n>\n> more"
    #expect(MarkdownText.streaming(source).stableSpans.isEmpty)
    let next = MarkdownText.streaming(source + "\n\noutside")
    #expect(next.stableSpans.map(\.text).joined().contains("more"))
    #expect(next.pendingSpans.map(\.text).joined().contains("outside"))
}

@Test func streamingCompletionResolvesLateReferences() {
    for ending in ["", "\n"] {
        let prefix = "[site][ref]\n\n| a | b |\n| --- | --- |\n| one | two |\n\nafter"
        let initial = MarkdownText.streaming(prefix)
        #expect(initial.stableSpans.allSatisfy { $0.link == nil })
        let source = prefix + "\n\n[ref]: https://example.com" + ending
        let final = MarkdownText.streaming(source, isComplete: true)
        #expect(final.pendingSpans.isEmpty)
        #expect(final.requiresFinalReflow)
        #expect(final.stableSpans.contains { $0.link == "https://example.com" })
        #expect(final.spans.map(\.text) == MarkdownText.spans(source).map(\.text))
    }
}

@Test func streamingEveryCharacterPreservesFullRendering() {
    let source = "前\n\n| a | b |\n| --- | --- |\n| 🐈 | é |\n\nnext\n"
    var received = ""
    for character in source {
        received.append(character)
        #expect(MarkdownText.streaming(received).spans.map(\.text) == MarkdownText.spans(received).map(\.text))
    }
    #expect(MarkdownText.streaming("\n").stableSpans.isEmpty)
    #expect(MarkdownText.streaming("", isComplete: true).requiresFinalReflow)
}
