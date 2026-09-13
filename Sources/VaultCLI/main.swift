import Foundation
import VaultCore
let args=CommandLine.arguments
if args.count<4 {print("vault-cli <scan|search|read|status> <vault> <cache> [query/path]");exit(1)}
do {
 let store=try VaultStore(root:URL(fileURLWithPath:args[2]),cache:URL(fileURLWithPath:args[3]))
 let result:Any
 switch args[1] {
 case "scan":result=try store.scan()
 case "search":result=try store.search(args.count>4 ? args[4]:"")
 case "read":result=try store.read(args[4])
 default:result=store.status()
 }
 let data=try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]);print(String(data:data,encoding:.utf8)!)
} catch {fputs(error.localizedDescription+"\n",stderr);exit(1)}
