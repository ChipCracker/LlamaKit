//
//  Calculator.swift
//  Safe arithmetic evaluator (Shunting-Yard → RPN) for the calculator tool.
//
//  Supports + − × ÷, modulo (%), power (^), parentheses, unary minus and
//  decimals. No `eval`/`NSExpression` → no way to run functions or arbitrary
//  code; purely numeric.
//
import Foundation

public enum Calculator {
    /// Evaluates an expression and returns the result as a string — or an
    /// (LLM-readable) error message.
    public static func evaluate(_ input: String) -> String {
        do {
            let tokens = try tokenize(input)
            let rpn = try toRPN(tokens)
            let value = try evalRPN(rpn)
            if value.isNaN || value.isInfinite { return "Error: result is undefined" }
            // Print integers without decimals.
            if value.rounded() == value && abs(value) < 1e15 {
                return String(Int64(value))
            }
            return String(value)
        } catch let e as CalcError {
            return "Error: \(e.message)"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Tokens

    private enum Token: Equatable {
        case number(Double)
        case op(Character)      // + - * / % ^
        case lparen, rparen
    }

    private struct CalcError: Error { let message: String }

    private static func tokenize(_ s: String) throws -> [Token] {
        var tokens: [Token] = []
        let chars = Array(s)
        var i = 0
        while i < chars.count {
            let c = chars[i]
            if c.isWhitespace { i += 1; continue }
            if c.isNumber || c == "." {
                var num = ""
                while i < chars.count, chars[i].isNumber || chars[i] == "." {
                    num.append(chars[i]); i += 1
                }
                guard let d = Double(num) else { throw CalcError(message: "invalid number \"\(num)\"") }
                tokens.append(.number(d))
                continue
            }
            switch c {
            case "+", "-", "*", "/", "%", "^": tokens.append(.op(c))
            case "×": tokens.append(.op("*"))
            case "÷", ":": tokens.append(.op("/"))
            case "(", "[": tokens.append(.lparen)
            case ")", "]": tokens.append(.rparen)
            default: throw CalcError(message: "illegal character \"\(c)\"")
            }
            i += 1
        }
        if tokens.isEmpty { throw CalcError(message: "empty expression") }
        return tokens
    }

    // MARK: - Shunting-Yard

    private static func precedence(_ op: Character) -> Int {
        switch op {
        case "+", "-": return 1
        case "*", "/", "%": return 2
        case "^": return 3
        case "u": return 4   // unary minus (negation)
        default: return 0
        }
    }
    private static func isRightAssoc(_ op: Character) -> Bool { op == "^" || op == "u" }

    private static func toRPN(_ tokens: [Token]) throws -> [Token] {
        var output: [Token] = []
        var ops: [Token] = []
        var prev: Token? = nil

        for t in tokens {
            switch t {
            case .number:
                output.append(t)
            case .op(let o):
                // Unary +/- : at the start or after an operator/open-paren. Unary
                // minus becomes the high-precedence right-assoc op `u` (negation);
                // unary plus is a no-op. Treating it as a real unary operator (not
                // "0 - x") keeps `3*-2 == -6` correct.
                let unary = (prev == nil) || prev == .op("+") || prev == .op("-")
                    || prev == .op("*") || prev == .op("/") || prev == .op("%")
                    || prev == .op("^") || prev == .op("u") || prev == .lparen
                if unary && (o == "-" || o == "+") {
                    if o == "-" { ops.append(.op("u")) }
                    prev = t
                    continue
                }
                while case let .op(top)? = ops.last,
                      precedence(top) > precedence(o)
                        || (precedence(top) == precedence(o) && !isRightAssoc(o)) {
                    output.append(ops.removeLast())
                }
                ops.append(t)
            case .lparen:
                ops.append(t)
            case .rparen:
                var found = false
                while let top = ops.last {
                    if top == .lparen { _ = ops.removeLast(); found = true; break }
                    output.append(ops.removeLast())
                }
                if !found { throw CalcError(message: "unbalanced parentheses") }
            }
            prev = t
        }
        while let top = ops.last {
            if top == .lparen || top == .rparen { throw CalcError(message: "unbalanced parentheses") }
            output.append(ops.removeLast())
        }
        return output
    }

    private static func evalRPN(_ rpn: [Token]) throws -> Double {
        var stack: [Double] = []
        for t in rpn {
            switch t {
            case .number(let d): stack.append(d)
            case .op("u"):   // unary negation
                guard let a = stack.popLast() else { throw CalcError(message: "incomplete expression") }
                stack.append(-a)
            case .op(let o):
                guard stack.count >= 2 else { throw CalcError(message: "incomplete expression") }
                let b = stack.removeLast(); let a = stack.removeLast()
                switch o {
                case "+": stack.append(a + b)
                case "-": stack.append(a - b)
                case "*": stack.append(a * b)
                case "/":
                    if b == 0 { throw CalcError(message: "division by zero") }
                    stack.append(a / b)
                case "%":
                    if b == 0 { throw CalcError(message: "modulo by zero") }
                    stack.append(a.truncatingRemainder(dividingBy: b))
                case "^": stack.append(pow(a, b))
                default: throw CalcError(message: "unknown operator")
                }
            default: throw CalcError(message: "invalid expression")
            }
        }
        guard stack.count == 1 else { throw CalcError(message: "incomplete expression") }
        return stack[0]
    }
}
