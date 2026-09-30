import Foundation
import Testing

@testable import loom

@Test func overwritingWideGlyphClearsItsOtherHalf() {
    var buffer = Buffer(width: 5, height: 1)
    buffer.put("中", width: 2, at: Point(x: 1, y: 0))
    buffer.put("x", width: 1, at: Point(x: 2, y: 0))
    #expect(buffer[1, 0].symbol == " ")
    #expect(buffer[2, 0].symbol == "x")
    #expect(buffer[2, 0].width == 1)
    buffer.put("中", width: 2, at: Point(x: 4, y: 0))
    #expect(buffer[4, 0].symbol == " ")
    buffer.put("ab", width: 1, at: Point(x: 0, y: 0))
    buffer.put("\u{1b}", width: 1, at: Point(x: 0, y: 0))
    #expect(buffer[0, 0].symbol == " ")
}
