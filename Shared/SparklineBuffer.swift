public struct SparklineBuffer {
    private var values: [Int] = []
    private let capacity: Int
    private static let characters: [Character] = ["▁", "▂", "▃", "▄", "▅", "▆", "▇", "█"]

    public init(capacity: Int) {
        precondition(capacity > 0)
        self.capacity = capacity
    }

    public mutating func append(_ value: Int) {
        values.append(value)
        if values.count > capacity {
            values.removeFirst(values.count - capacity)
        }
    }

    public var range: (min: Int, max: Int) {
        (values.min() ?? 0, values.max() ?? 0)
    }

    public func render() -> String {
        guard !values.isEmpty else { return "" }
        var lower = range.min
        var upper = range.max
        if upper - lower < 5 {
            let middle = (upper + lower) / 2
            lower = max(0, middle - 5)
            upper = middle + 5
        }
        return String(values.map { value in
            let index = max(0, min(7, (value - lower) * 7 / (upper - lower)))
            return Self.characters[index]
        })
    }
}
