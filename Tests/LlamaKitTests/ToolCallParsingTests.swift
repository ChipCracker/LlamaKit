import XCTest
@testable import LlamaKit

final class ToolCallParsingTests: XCTestCase {
    let format = Qwen35ChatFormat()

    func testWellFormed() {
        let s = """
        Let me calculate that.
        <tool_call>
        <function=calculate>
        <parameter=expression>
        (3+4)*2
        </parameter>
        </function>
        </tool_call>
        """
        let call = format.parseToolCall(s)
        XCTAssertEqual(call?.name, "calculate")
        XCTAssertEqual(call?.arguments["expression"], "(3+4)*2")
    }

    func testMultipleParameters() {
        let s = """
        <function=web_search>
        <parameter=query>
        eiffel tower height
        </parameter>
        <parameter=lang>
        en
        </parameter>
        </function>
        """
        let call = format.parseToolCall(s)
        XCTAssertEqual(call?.name, "web_search")
        XCTAssertEqual(call?.arguments["query"], "eiffel tower height")
        XCTAssertEqual(call?.arguments["lang"], "en")
    }

    func testNoToolCall() {
        XCTAssertNil(format.parseToolCall("Just a normal answer, no tools."))
    }

    func testEmptyNameIsNil() {
        XCTAssertNil(format.parseToolCall("<function=></function>"))
    }
}
