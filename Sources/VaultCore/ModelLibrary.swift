import Foundation

public struct LocalModel: Sendable {
    public let id:String,name:String,architecture:String,precision:String,path:URL,bytes:Int,context:Int
    public var recommended:Bool=false
    public var json:[String:Any] {
        #if os(iOS)
        let availableContext=min(4096,context),maxOutput=1024
        #else
        let availableContext=context,maxOutput=4096
        #endif
        return ["id":id,"name":name,"architecture":architecture,"precision":precision,"bytes":bytes,"context":availableContext,"maxOutput":maxOutput,"provider":"local","installed":true,"offline":true,"recommended":recommended]
    }
}
/// Model files are data, outside the research vault. No Python or remote code is imported.
public enum ModelLibrary {
    public static var root:URL {
        if let path=ProcessInfo.processInfo.environment["VAULT_MODELS_DIR"],!path.isEmpty{return URL(fileURLWithPath:path,isDirectory:true)}
        #if os(iOS)
        return FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Models")
        #else
        return FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Archii Vault/Models")
        #endif
    }
    public static var bundledRoot:URL? {Bundle.main.resourceURL?.appendingPathComponent("Models")}
    public static let architectures:Set<String>=["llama","qwen2","qwen3","qwen3_5","qwen3_5_text","gemma","gemma2","gemma3_text","gemma4","gemma4_text","gemma4_unified","mistral","phi3","smollm3"]
    public static func inspect(_ folder:URL)throws->LocalModel {
        let fm=FileManager.default
        guard !fm.fileExists(atPath:folder.appendingPathComponent(".disabled").path)else{throw VaultError.message("This model has been removed from the model chooser.")}
        guard (try folder.resourceValues(forKeys:[.isDirectoryKey,.isSymbolicLinkKey])).isSymbolicLink != true else{throw VaultError.message("Copy the model files themselves, rather than a symbolic link.")}
        let files=try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:[.isRegularFileKey,.isSymbolicLinkKey,.fileSizeKey],options:.skipsHiddenFiles)
        for f in files {if try f.resourceValues(forKeys:[.isSymbolicLinkKey]).isSymbolicLink==true{throw VaultError.message("Model folders must contain regular files, not symbolic links.")}}
        func json(_ name:String)throws->[String:Any] {let f=folder.appendingPathComponent(name);guard let size=try f.resourceValues(forKeys:[.fileSizeKey]).fileSize,size<=32*1024*1024,let data=try JSONSerialization.jsonObject(with:Data(contentsOf:f)) as? [String:Any]else{throw VaultError.message("Invalid model metadata: "+name)};return data}
        let config=try json("config.json"),text=config["text_config"] as? [String:Any] ?? config,architecture=config["model_type"] as? String ?? ""
        guard architectures.contains(architecture)else{throw VaultError.message("This build does not support model architecture ‘\(architecture)’. Choose a supported MLX model folder.")}
        let tokenizer=try json("tokenizer_config.json")
        guard fm.fileExists(atPath:folder.appendingPathComponent("tokenizer.json").path)else{throw VaultError.message("Add tokenizer.json to this model folder.")}
        guard tokenizer["chat_template"] != nil || fm.fileExists(atPath:folder.appendingPathComponent("chat_template.jinja").path)else{throw VaultError.message("This model needs an instruction/chat template.")}
        let weights=files.filter{$0.pathExtension=="safetensors"}
        guard !weights.isEmpty else{throw VaultError.message("Add the model’s .safetensors weights to this folder. GGUF needs a different runtime and is not supported yet.")}
        var bytes=0
        for f in weights {let r=try f.resourceValues(forKeys:[.isRegularFileKey,.fileSizeKey]);guard r.isRegularFile==true,let size=r.fileSize,size>16 else{throw VaultError.message("Incomplete weights: "+f.lastPathComponent)}
            let handle=try FileHandle(forReadingFrom:f);defer{try? handle.close()}
            let prefix=try handle.read(upToCount:8) ?? Data(),length=prefix.enumerated().reduce(UInt64(0)){$0 | (UInt64($1.element)<<($1.offset*8))}
            guard prefix.count==8,length>0,length<=16*1024*1024,Int(length)+8<size,let header=try handle.read(upToCount:Int(length)),header.count==Int(length),let tensors=try JSONSerialization.jsonObject(with:header) as? [String:Any],!tensors.isEmpty else{throw VaultError.message("Invalid or incomplete safetensors header: "+f.lastPathComponent)}
            for (key,value) in tensors where key != "__metadata__" {guard let tensor=value as? [String:Any],let offsets=tensor["data_offsets"] as? [Int],offsets.count==2,offsets[0]>=0,offsets[1]>=offsets[0],offsets[1]<=size-Int(length)-8 else{throw VaultError.message("Weight data is still copying or incomplete: "+f.lastPathComponent)}}
            bytes+=size}
        let index=folder.appendingPathComponent("model.safetensors.index.json")
        if fm.fileExists(atPath:index.path){let map=try json("model.safetensors.index.json")["weight_map"] as? [String:String] ?? [:];guard !map.isEmpty,Set(map.values).isSubset(of:Set(weights.map(\.lastPathComponent)))else{throw VaultError.message("Some weight shards are missing. Finish copying the model, then refresh.")}}
        let manifest=(try? json("vault-model.json")) ?? [:]
        let precision=(config["quantization"] as? [String:Any]).flatMap{$0["bits"] as? Int}.map{"\($0)-bit"} ?? (manifest["precision"] as? String) ?? (text["torch_dtype"] as? String) ?? (text["dtype"] as? String) ?? "Original"
        return LocalModel(id:folder.lastPathComponent,name:manifest["name"] as? String ?? folder.lastPathComponent,architecture:architecture,precision:precision,path:folder,bytes:bytes,context:min(16384,max(1024,text["max_position_embeddings"] as? Int ?? 4096)),recommended:manifest["recommended"] as? Bool ?? false)
    }
    public static func catalog()->[String:Any] {
        let fm=FileManager.default;try? fm.createDirectory(at:root,withIntermediateDirectories:true)
        var models=[[String:Any]](),issues=[[String:String]]()
        for folder in (try? fm.contentsOfDirectory(at:root,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles)) ?? [] {
            if fm.fileExists(atPath:folder.appendingPathComponent(".disabled").path){continue}
            guard (try? folder.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true else{continue}
            do{models.append(try inspect(folder).json)}catch{issues.append(["name":folder.lastPathComponent,"message":error.localizedDescription])}
        }
        if let bundledRoot {
            for folder in (try? fm.contentsOfDirectory(at:bundledRoot,includingPropertiesForKeys:[.isDirectoryKey],options:.skipsHiddenFiles)) ?? [] {
                guard !models.contains(where:{$0["id"] as? String==folder.lastPathComponent}) else{continue}
                if let model=try? inspect(folder){models.append(model.json)}
            }
        }
        return ["models":models.sorted{($0["bytes"] as? Int ?? 0)<($1["bytes"] as? Int ?? 0)},"issues":issues,"folder":root.path]
    }
    public static func selected(_ id:String)throws->LocalModel {
        guard !id.isEmpty,id != ".",id != "..",!id.contains("/"),!id.contains("\\")else{throw VaultError.message("Choose an installed model first.")}
        let installed=root.appendingPathComponent(id)
        if FileManager.default.fileExists(atPath:installed.path){return try inspect(installed)}
        if let bundledRoot,FileManager.default.fileExists(atPath:bundledRoot.appendingPathComponent(id).path){return try inspect(bundledRoot.appendingPathComponent(id))}
        throw VaultError.message("Choose an installed model or install a starter model in Settings → Models & chat.")
    }
    @discardableResult public static func importFolder(_ source:URL)throws->LocalModel {
        let validated=try inspect(source),fm=FileManager.default
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        let destination=root.appendingPathComponent(source.lastPathComponent)
        if source.standardizedFileURL==destination.standardizedFileURL{return validated}
        guard !fm.fileExists(atPath:destination.path)else{throw VaultError.message("That model is already installed. Rename the new model folder to keep both versions.")}
        let staging=root.appendingPathComponent(".import-"+UUID().uuidString);try fm.createDirectory(at:staging,withIntermediateDirectories:true)
        defer{try? fm.removeItem(at:staging)}
        for f in try fm.contentsOfDirectory(at:source,includingPropertiesForKeys:[.isRegularFileKey]) where ["json","safetensors","jinja","txt","model"].contains(f.pathExtension) || ["LICENSE","NOTICE","README.md"].contains(f.lastPathComponent) {
            guard (try? f.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile)==true else{continue};try fm.copyItem(at:f,to:staging.appendingPathComponent(f.lastPathComponent))
        }
        _ = try inspect(staging);try fm.moveItem(at:staging,to:destination);return try inspect(destination)
    }
}
