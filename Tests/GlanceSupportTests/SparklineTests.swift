import Testing
@testable import GlanceSupport

@Test func emptySparkline() {
    let buffer = SparklineBuffer(capacity: 3)
    #expect(buffer.render().isEmpty)
    #expect(buffer.range.min == 0)
    #expect(buffer.range.max == 0)
}

@Test func boundedSparkline() {
    var buffer = SparklineBuffer(capacity: 3)
    for value in [0, 10, 20, 30] {
        buffer.append(value)
    }
    #expect(buffer.range.min == 10)
    #expect(buffer.range.max == 30)
    #expect(buffer.render().count == 3)
}

@Test func constantSparkline() {
    var buffer = SparklineBuffer(capacity: 4)
    for _ in 0..<4 {
        buffer.append(50)
    }
    #expect(buffer.render().count == 4)
}
