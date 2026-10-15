import Foundation

struct TestFailure: Error, CustomStringConvertible {
    let description: String
}

struct TestCase {
    let name: String
    let body: () throws -> Void

    init(name: String, body: @escaping () throws -> Void) {
        self.name = name
        self.body = body
    }
}

func expect(
    _ condition: @autoclosure () throws -> Bool,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    do {
        if try condition() {
            return
        }
    } catch let failure as TestFailure {
        throw TestFailure(description: "\(failure.description) (\(file):\(line))")
    } catch {
        throw TestFailure(description: "expression threw \(type(of: error)): \(error) (\(file):\(line))")
    }
    let text = message()
    let detail = text.isEmpty ? "expected condition to be true" : text
    throw TestFailure(description: "\(detail) (\(file):\(line))")
}

func expectEqual<T: Equatable>(
    _ actual: @autoclosure () throws -> T,
    _ expected: @autoclosure () throws -> T,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: UInt = #line
) throws {
    do {
        let lhs = try actual()
        let rhs = try expected()
        if lhs == rhs {
            return
        }
        let text = message()
        let prefix = text.isEmpty ? "" : "\(text): "
        throw TestFailure(description: "\(prefix)expected \(rhs), got \(lhs) (\(file):\(line))")
    } catch let failure as TestFailure {
        throw TestFailure(description: "\(failure.description)")
    } catch {
        throw TestFailure(description: "expression threw \(type(of: error)): \(error) (\(file):\(line))")
    }
}

func expectThrows<E: Error>(
    _ expectedType: E.Type,
    _ message: @autoclosure () -> String = "",
    file: StaticString = #fileID,
    line: UInt = #line,
    _ body: () throws -> Void
) throws {
    do {
        try body()
    } catch let thrown as E {
        _ = thrown
        return
    } catch let failure as TestFailure {
        throw TestFailure(description: failure.description)
    } catch {
        let text = message()
        let prefix = text.isEmpty ? "" : "\(text): "
        throw TestFailure(description: "\(prefix)expected \(E.self), got \(type(of: error)) (\(file):\(line))")
    }
    let text = message()
    let prefix = text.isEmpty ? "" : "\(text): "
    throw TestFailure(description: "\(prefix)expected \(E.self) but nothing was thrown (\(file):\(line))")
}
