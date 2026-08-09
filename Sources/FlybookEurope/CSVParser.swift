import Foundation

enum CSVParser {
    /// Parses RFC 4180 style CSV while accepting CRLF, LF, and CR line endings.
    /// Iterating over Unicode scalars is intentional: Swift may represent CRLF
    /// as one extended grapheme cluster when iterating over `Character`.
    static func parse(_ text: String, delimiter: Unicode.Scalar = ",") -> [[String]] {
        let scalars = Array(text.unicodeScalars)
        var rows: [[String]] = []
        var row: [String] = []
        var field = String.UnicodeScalarView()
        var isInsideQuotedField = false
        var index = 0

        func appendField() {
            row.append(String(field))
            field.removeAll(keepingCapacity: true)
        }

        func appendRow() {
            appendField()
            if row.contains(where: { !$0.isEmpty }) {
                rows.append(row)
            }
            row.removeAll(keepingCapacity: true)
        }

        while index < scalars.count {
            let scalar = scalars[index]

            if index == 0, scalar == "\u{FEFF}" {
                index += 1
                continue
            }

            if scalar == "\"" {
                if isInsideQuotedField {
                    if index + 1 < scalars.count, scalars[index + 1] == "\"" {
                        field.append("\"")
                        index += 2
                        continue
                    }
                    isInsideQuotedField = false
                } else if field.isEmpty {
                    isInsideQuotedField = true
                } else {
                    field.append(scalar)
                }
                index += 1
                continue
            }

            if scalar == delimiter, !isInsideQuotedField {
                appendField()
                index += 1
                continue
            }

            if !isInsideQuotedField, scalar == "\r" || scalar == "\n" {
                if scalar == "\r", index + 1 < scalars.count, scalars[index + 1] == "\n" {
                    index += 1
                }
                appendRow()
                index += 1
                continue
            }

            field.append(scalar)
            index += 1
        }

        if !field.isEmpty || !row.isEmpty {
            appendRow()
        }

        return rows
    }
}
