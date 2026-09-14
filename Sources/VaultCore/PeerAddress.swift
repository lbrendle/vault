import Foundation

/// Direct routes still authenticate with the vault's pairing key.
public struct PeerAddress:Equatable {
    public let host:String,port:UInt16
    public static func privateIPv4(_ host:String)->Bool {
        let pieces=host.split(separator:".",omittingEmptySubsequences:false)
        guard pieces.count==4,pieces.allSatisfy({!$0.isEmpty && $0.allSatisfy(\.isNumber)}),
              pieces.allSatisfy({$0.count==1 || !$0.hasPrefix("0")}) else{return false}
        let p=pieces.compactMap{Int($0)}
        guard p.count==4,p.allSatisfy({(0...255).contains($0)}) else{return false}
        return p[0]==10 || (p[0]==192 && p[1]==168) || (p[0]==172 && (16...31).contains(p[1])) || (p[0]==169 && p[1]==254) || (p[0]==100 && (64...127).contains(p[1]))
    }
    public init(_ address:String)throws {
        let parts=address.trimmingCharacters(in:.whitespacesAndNewlines).lowercased().split(separator:":",omittingEmptySubsequences:false)
        guard parts.count==2,let port=UInt16(parts[1]),port>0 else{throw VaultError.message("Enter your Mac's LAN or Tailscale address and port, such as 100.80.20.10:50000.")}
        let host=String(parts[0]),labels=host.split(separator:".",omittingEmptySubsequences:false)
        let dns=(host.hasSuffix(".ts.net") && labels.count>=4) || (host.hasSuffix(".local") && labels.count>=2)
        let validDNS=dns && host.count<=253 && labels.allSatisfy{label in !label.isEmpty && label.count<=63 && !label.hasPrefix("-") && !label.hasSuffix("-") && label.utf8.allSatisfy{($0>=97 && $0<=122) || ($0>=48 && $0<=57) || $0==45}}
        guard Self.privateIPv4(host) || validDNS else{throw VaultError.message("Use a private LAN address, a Tailscale 100.x address or full .ts.net name, or a .local name.")}
        self.host=host;self.port=port
    }
}
