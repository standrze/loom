import Testing

@testable import loom

@Test func symbolAnimationUsesElapsedTimeAndFrameBoundaries() {
    let animation = SymbolAnimation(frames: [.init("a"), .init("b")], frameDuration: 0.25)
    #expect(animation.sample(at: -1).symbol == "a")
    #expect(animation.sample(at: 0.249).symbol == "a")
    #expect(animation.sample(at: 0.25).symbol == "b")
    #expect(animation.sample(at: 0.5).symbol == "a")
    #expect(animation.sample(at: .infinity).symbol == "a")
    #expect(animation.nextFrame(after: 0.125) == 0.125)
    #expect(SymbolAnimation(frames: [], frameDuration: 0).nextFrame(after: 0) == nil)
}

@Test func builtInAnimationsHaveDistinctCadencesAndPreserveBackground() {
    #expect(SymbolAnimation.spinner().frames.count == 10)
    #expect(SymbolAnimation.activity().frames.map(\.symbol) == ["○", "◎", "◉", "◎"])
    #expect(SymbolAnimation.activity().frameDuration > SymbolAnimation.spinner().frameDuration)
    let style = Style(background: .indexed(2), bold: true)
    let pulse = SymbolAnimation.pulse(low: 40, high: 140, style: style)
    #expect(pulse.frames[0].style.foreground == .rgb(40, 40, 40))
    #expect(pulse.frames[40].style.foreground == .rgb(140, 140, 140))
    #expect(pulse.frames.allSatisfy { $0.symbol == "◆" && $0.style.background == .indexed(2) && $0.style.bold })
}

@Test func colorBlendKeepsExplicitRgbAndRejectsTerminalColors() {
    #expect(Color.rgb(0, 0, 0).blended(toward: .rgb(10, 20, 30), amount: 0.5) == .rgb(5, 10, 15))
    #expect(Color.rgb(1, 1, 1).blended(toward: .rgb(9, 9, 9), amount: 2) == .rgb(9, 9, 9))
    #expect(Color.rgb(1, 1, 1).blended(toward: .rgb(9, 9, 9), amount: .nan) == .rgb(1, 1, 1))
    #expect(Color.terminalDefault.blended(toward: .rgb(1, 2, 3), amount: 1) == nil)
    #expect(Color.rgb(1, 2, 3).blended(toward: .indexed(4), amount: 1) == nil)
}

@Test func diagonalShineSweepsThenRests() {
    var seconds = 0.0
    while seconds < 10 {
        for step in 0...20 {
            let opacity = DiagonalShine.opacity(diagonal: Double(step) / 20, seconds: seconds)
            #expect((0...1).contains(opacity))
        }
        seconds += 0.13
    }

    func brightest(at seconds: Double) -> Double {
        (0...100).map { Double($0) / 100 }.max { lhs, rhs in
            DiagonalShine.opacity(diagonal: lhs, seconds: seconds)
                < DiagonalShine.opacity(diagonal: rhs, seconds: seconds)
        }!
    }
    let early = brightest(at: 0.1)
    let mid = brightest(at: 0.4)
    let late = brightest(at: 0.7)
    #expect(early < mid)
    #expect(mid < late)
    #expect(DiagonalShine.opacity(diagonal: 0.5, seconds: 6) < 0.2)
    #expect(DiagonalShine.frame(at: 0) == 0)
    #expect(DiagonalShine.frame(at: 1) == 12)
    #expect(DiagonalShine.delayUntilNextFrame(after: 0) == 1.0 / DiagonalShine.framesPerSecond)
}
