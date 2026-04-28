import AppKit
import Carbon
import CoreServices
import CoreGraphics
import ServiceManagement
import UniformTypeIdentifiers

enum ArithmeticEvaluator {
    static func evaluate(_ input: String) -> String? {
        let expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isArithmeticInput(expression) else { return nil }

        do {
            var parser = ArithmeticParser(expression)
            let value = try parser.parse()
            guard value.isFinite else { return nil }
            return format(value)
        } catch {
            return nil
        }
    }

    static func isArithmeticInput(_ input: String) -> Bool {
        let expression = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !expression.isEmpty else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "0123456789+-*/×÷()., \t\n")
        return expression.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }

    static func shouldStoreInHistory(_ input: String) -> Bool {
        containsBinaryArithmeticOperator(input.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private static func containsBinaryArithmeticOperator(_ value: String) -> Bool {
        var previousNonWhitespace: UnicodeScalar?

        for scalar in value.unicodeScalars {
            if CharacterSet.whitespacesAndNewlines.contains(scalar) {
                continue
            }

            if "+-*/×÷".unicodeScalars.contains(scalar) {
                if let previousNonWhitespace,
                   !"+-*/×÷(".unicodeScalars.contains(previousNonWhitespace) {
                    return true
                }
            }

            previousNonWhitespace = scalar
        }

        return false
    }

    private static func format(_ value: Double) -> String {
        let rounded = value.rounded()
        if abs(value - rounded) < 0.0000000001,
           rounded >= Double(Int64.min),
           rounded <= Double(Int64.max) {
            return String(Int64(rounded))
        }

        return resultFormatter.string(from: NSNumber(value: value)) ?? String(format: "%.10g", value)
    }

    private static let resultFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 10
        formatter.usesGroupingSeparator = false
        return formatter
    }()
}
enum ArithmeticEvaluationError: Error {
    case expectedNumber
    case unexpectedInput
    case unmatchedParenthesis
    case divisionByZero
}
struct ArithmeticParser {
    private let scalars: [UnicodeScalar]
    private var index = 0

    init(_ expression: String) {
        scalars = Array(expression.unicodeScalars)
    }

    mutating func parse() throws -> Double {
        let value = try parseExpression()
        skipWhitespace()
        guard index == scalars.count else {
            throw ArithmeticEvaluationError.unexpectedInput
        }
        return value
    }

    private mutating func parseExpression() throws -> Double {
        var value = try parseTerm()

        while true {
            skipWhitespace()
            if match("+") {
                value += try parseTerm()
            } else if match("-") {
                value -= try parseTerm()
            } else {
                return value
            }
        }
    }

    private mutating func parseTerm() throws -> Double {
        var value = try parseFactor()

        while true {
            skipWhitespace()
            if match("*") || match("×") {
                value *= try parseFactor()
            } else if match("/") || match("÷") {
                let divisor = try parseFactor()
                guard divisor != 0 else {
                    throw ArithmeticEvaluationError.divisionByZero
                }
                value /= divisor
            } else {
                return value
            }
        }
    }

    private mutating func parseFactor() throws -> Double {
        skipWhitespace()

        if match("+") {
            return try parseFactor()
        }

        if match("-") {
            let value = try parseFactor()
            return -value
        }

        if match("(") {
            let value = try parseExpression()
            guard match(")") else {
                throw ArithmeticEvaluationError.unmatchedParenthesis
            }
            return value
        }

        return try parseNumber()
    }

    private mutating func parseNumber() throws -> Double {
        skipWhitespace()
        let start = index
        var sawDigit = false
        var sawDecimal = false

        while index < scalars.count {
            let scalar = scalars[index]

            if CharacterSet.decimalDigits.contains(scalar) {
                sawDigit = true
                index += 1
            } else if scalar == ".", !sawDecimal {
                sawDecimal = true
                index += 1
            } else if scalar == "," {
                index += 1
            } else {
                break
            }
        }

        guard sawDigit else {
            throw ArithmeticEvaluationError.expectedNumber
        }

        let numberText = String(String.UnicodeScalarView(Array(scalars[start..<index])))
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(numberText) else {
            throw ArithmeticEvaluationError.expectedNumber
        }
        return value
    }

    private mutating func skipWhitespace() {
        while index < scalars.count,
              CharacterSet.whitespacesAndNewlines.contains(scalars[index]) {
            index += 1
        }
    }

    private mutating func match(_ value: String) -> Bool {
        guard let scalar = value.unicodeScalars.first,
              index < scalars.count,
              scalars[index] == scalar else {
            return false
        }

        index += 1
        return true
    }
}
