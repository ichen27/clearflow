import Foundation

/// Decides from accessibility facts whether Command-V can insert text at a cursor.
public enum Editability {
    static let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
    /// - Parameters:
    ///   - insideEditableContent: the element reports an editable ancestor, as web
    ///     `contenteditable` editors (Slack, Notion, Gmail, ChatGPT) do.
    ///   - exposesTextSelection: the element reports a text selection range; together
    ///     with a settable value this identifies custom text views but not sliders.
    public static func allows(role: String, insideEditableContent: Bool,
                              exposesTextSelection: Bool, valueSettable: Bool) -> Bool {
        textRoles.contains(role) || insideEditableContent || (exposesTextSelection && valueSettable)
    }
}

/// The field value a successful paste should produce, when the app exposes enough to know.
public enum PastePrediction {
    public static func result(of text: String, in value: String?, location: Int?, length: Int?) -> String? {
        guard let value, let location, let length, location >= 0, length >= 0 else { return nil }
        let current = value as NSString
        guard location + length <= current.length else { return nil }
        return current.replacingCharacters(in: NSRange(location: location, length: length), with: text)
    }
}
