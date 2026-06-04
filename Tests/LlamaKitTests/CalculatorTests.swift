import XCTest
@testable import LlamaKitTools

final class CalculatorTests: XCTestCase {
    func testBasics() {
        XCTAssertEqual(Calculator.evaluate("(3+4)*2"), "14")
        XCTAssertEqual(Calculator.evaluate("1234*5678"), "7006652")
        XCTAssertEqual(Calculator.evaluate("2^10"), "1024")
        XCTAssertEqual(Calculator.evaluate("10/4"), "2.5")
    }

    func testPrecedenceAndAssociativity() {
        XCTAssertEqual(Calculator.evaluate("2+3*4"), "14")       // * before +
        XCTAssertEqual(Calculator.evaluate("2^3^2"), "512")      // ^ right-assoc → 2^(3^2)
        XCTAssertEqual(Calculator.evaluate("(2+3)*4"), "20")
    }

    func testUnaryMinus() {
        XCTAssertEqual(Calculator.evaluate("-5+3"), "-2")
        XCTAssertEqual(Calculator.evaluate("3*-2"), "-6")
        XCTAssertEqual(Calculator.evaluate("-(2+3)"), "-5")
    }

    func testModuloAndAliases() {
        XCTAssertEqual(Calculator.evaluate("10%3"), "1")
        XCTAssertEqual(Calculator.evaluate("6×7"), "42")        // × alias
        XCTAssertEqual(Calculator.evaluate("84÷2"), "42")       // ÷ alias
    }

    func testErrors() {
        XCTAssertEqual(Calculator.evaluate("1/0"), "Error: division by zero")
        XCTAssertEqual(Calculator.evaluate("(1+2"), "Error: unbalanced parentheses")
        XCTAssertEqual(Calculator.evaluate("abc"), "Error: illegal character \"a\"")
        XCTAssertEqual(Calculator.evaluate(""), "Error: empty expression")
    }
}
