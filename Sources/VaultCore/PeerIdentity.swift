import Foundation

public enum PeerIdentity {
    /// Bonjour appends a collision suffix such as " (2)" to service names.
    /// The device ID stays fixed; the advertised display name is not its identity.
    public static func device(in serviceName:String,group:String,excluding local:String)->String? {
        let prefix=String(group.prefix(12))+"-"
        guard serviceName.hasPrefix(prefix) else{return nil}
        let tail=String(serviceName.dropFirst(prefix.count)),id=String(tail.prefix(32))
        guard id.count==32,id.allSatisfy({$0.isHexDigit}),id != local else{return nil}
        let suffix=String(tail.dropFirst(32))
        guard suffix.isEmpty || suffix.range(of:#"^ \([0-9]+\)$"#,options:.regularExpression) != nil else{return nil}
        return id
    }
}
