/// A physical Fn press toggles only on release, and only if it was used alone.
public struct FnTap {
    private var down = false
    private var eligible = false
    public var isPressed: Bool { down }
    public init(heldAtStart: Bool = false) { down = heldAtStart }
    public mutating func cancelChord() { eligible = false }
    public mutating func flagsChanged(keyCode: UInt16, fnDown: Bool, otherModifiers: Bool) -> Bool {
        if otherModifiers { eligible = false }
        guard keyCode == 63 else {
            if down { eligible = false }
            return false
        }
        if fnDown {
            if !down { down = true; eligible = !otherModifiers }
            return false
        }
        let fire = down && eligible && !otherModifiers
        down = false; eligible = false
        return fire
    }
}
