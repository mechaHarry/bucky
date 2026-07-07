import Foundation

enum ApplicationQueryRoute: Equatable {
    case applications(query: String)
    case calculator(expression: String)
    case dictionary(term: String)

    init(query: String) {
        guard let markerIndex = query.firstIndex(where: { !$0.isWhitespace }) else {
            self = .applications(query: query)
            return
        }

        let marker = query[markerIndex]
        let payloadStart = query.index(after: markerIndex)
        let payload = String(query[payloadStart...]).trimmingCharacters(in: .whitespacesAndNewlines)

        switch marker {
        case "=":
            self = .calculator(expression: payload)
        case "?":
            self = .dictionary(term: payload)
        default:
            self = .applications(query: query)
        }
    }

    var calculatorExpression: String? {
        guard case let .calculator(expression) = self else { return nil }
        return expression
    }

    var dictionaryTerm: String? {
        guard case let .dictionary(term) = self else { return nil }
        return term
    }
}
