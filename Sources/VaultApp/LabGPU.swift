import Foundation
import MLX
import Metal

/// A small, explicit graph bridge. The editable Python program defines the graph;
/// MLX differentiates and executes it on the local Apple GPU.
enum LabGPU {
    static func dispatch(_ request:String)->String {
        do {
            guard let r=try JSONSerialization.jsonObject(with:Data(request.utf8)) as? [String:Any] else{throw problem("Invalid GPU request")}
            guard let device=MTLCreateSystemDefaultDevice() else{throw problem("No Metal device is available")}
            if r["method"] as? String == "info" {return encode(["backend":"MLX Metal","device":device.name,"local":true])}
            if r["method"] as? String == "kernel" {return encode(try kernel(r,device:device))}
            guard let nodes=r["nodes"] as? [[String:Any]],nodes.count<=512,!nodes.isEmpty,
                  let output=r["output"] as? Int,output>=0,output<nodes.count else{throw problem("Invalid or oversized tensor graph")}
            var shapes=[[Int]](),total=0
            for (i,n) in nodes.enumerated() {
                guard let shape=n["shape"] as? [Int],shape.count<=4,shape.allSatisfy({$0>0 && $0<=8192}),
                      let op=n["op"] as? String else{throw problem("Invalid tensor shape")}
                let size=shape.reduce(1,*)
                guard size<=2_000_000 else{throw problem("A tensor exceeds this lab's current execution budget")}
                total+=size;guard total<=8_000_000 else{throw problem("The graph exceeds this lab's current execution budget")}
                let input=n["inputs"] as? [Int] ?? []
                guard input.allSatisfy({$0>=0 && $0<i}) else{throw problem("A graph input is invalid")}
                if op=="array" {
                    guard let values=n["values"] as? [NSNumber],values.count==size,values.allSatisfy({$0.doubleValue.isFinite}) else{throw problem("Tensor values do not match its shape")}
                }else if ["add","sub","mul","div","matmul"].contains(op) {
                    guard input.count==2 else{throw problem("Binary operation requires two inputs")}
                    let a=shapes[input[0]],b=shapes[input[1]]
                    if op=="matmul" {
                        guard a.count==2,b.count==2,a[1]==b[0],shape==[a[0],b[1]] else{throw problem("Matrix dimensions do not agree")}
                    }else {
                        var result=[Int]();let count=max(a.count,b.count)
                        for j in 0..<count {let x=j<a.count ? a[a.count-1-j]:1,y=j<b.count ? b[b.count-1-j]:1;guard x==y || x==1 || y==1 else{throw problem("Tensor shapes cannot broadcast")};result.insert(max(x,y),at:0)}
                        guard result==shape else{throw problem("Incorrect broadcast output shape")}
                    }
                }else if ["relu","exp","log","neg","sum","mean","transpose","tanh"].contains(op) {
                    guard input.count==1 else{throw problem("Unary operation requires one input")}
                    let source=shapes[input[0]]
                    let expected:[Int]
                    if op=="sum" || op=="mean" {expected=[]}
                    else if op=="transpose" {guard source.count==2 else{throw problem("Transpose currently requires a matrix")};expected=Array(source.reversed())}
                    else{expected=source}
                    guard shape==expected else{throw problem("Incorrect output shape")}
                }else{throw problem("Unsupported tensor operation: \(op)")}
                shapes.append(shape)
            }
            let parameters=r["parameters"] as? [Int] ?? []
            guard parameters.allSatisfy({$0>=0 && $0<nodes.count && nodes[$0]["op"] as? String=="array"}),Set(parameters).count==parameters.count else{throw problem("Invalid gradient parameters")}
            if !parameters.isEmpty && !shapes[output].isEmpty{throw problem("Gradients require a scalar loss")}
            #if os(iOS)
            guard os_proc_available_memory()>UInt64(total*4*6+64*1024*1024) else{throw problem("There is not enough free memory for this graph")}
            #endif
            let answer:[String:Any]=Device.withDefaultDevice(.gpu) {
                let leaves=nodes.enumerated().filter{$0.element["op"] as? String=="array"}.map{$0.offset}
                let arrays=leaves.map{index in MLXArray((nodes[index]["values"] as! [NSNumber]).map{$0.floatValue},shapes[index])}
                let positions=Dictionary(uniqueKeysWithValues:leaves.enumerated().map{($0.element,$0.offset)})
                let evaluate:([MLXArray])->[MLXArray]={values in
                    var computed=[MLXArray]()
                    for (i,n) in nodes.enumerated() {
                        let inputs=n["inputs"] as? [Int] ?? []
                        func a(_ j:Int)->MLXArray{computed[inputs[j]]}
                        let result:MLXArray
                        switch n["op"] as! String {
                        case "array":result=values[positions[i]!]
                        case "add":result=a(0)+a(1)
                        case "sub":result=a(0)-a(1)
                        case "mul":result=a(0)*a(1)
                        case "div":result=a(0)/a(1)
                        case "matmul":result=matmul(a(0),a(1))
                        case "relu":result=maximum(a(0),0)
                        case "exp":result=exp(a(0))
                        case "log":result=log(a(0))
                        case "tanh":result=tanh(a(0))
                        case "neg":result = -a(0)
                        case "sum":result=sum(a(0))
                        case "mean":result=mean(a(0))
                        case "transpose":result=a(0).T
                        default:preconditionFailure("Graph validation must precede execution")
                        }
                        computed.append(result)
                    }
                    return [computed[output]]
                }
                let value:MLXArray,gradients:[MLXArray]
                if parameters.isEmpty {value=evaluate(arrays)[0];gradients=[]}
                else {let result=valueAndGrad(evaluate,argumentNumbers:parameters.map{positions[$0]!})(arrays);value=result.0[0];gradients=result.1}
                eval([value]+gradients)
                return ["value":value.asArray(Float.self),"shape":value.shape,"gradients":gradients.map{$0.asArray(Float.self)},"backend":"MLX Metal","device":device.name,"local":true]
            }
            return encode(answer)
        }catch{return encode(["error":error.localizedDescription])}
    }
    private static func kernel(_ r:[String:Any],device:MTLDevice)throws->[String:Any] {
        guard let source=r["source"] as? String,source.utf8.count<=65_536,
              let name=r["function"] as? String,name.range(of:"^[A-Za-z_][A-Za-z0-9_]*$",options:.regularExpression) != nil,
              let inputs=r["inputs"] as? [[NSNumber]],inputs.count<=8,
              let count=r["count"] as? Int,count>0,count<=2_000_000,
              inputs.allSatisfy({!$0.isEmpty && $0.count<=2_000_000 && $0.allSatisfy{$0.doubleValue.isFinite}}),
              inputs.reduce(count,{$0+$1.count})<=8_000_000 else{throw problem("Invalid or oversized Metal kernel request")}
        #if os(iOS)
        guard os_proc_available_memory()>128*1024*1024 else{throw problem("There is not enough free memory to compile this kernel")}
        #endif
        let started=Date()
        let options=MTLCompileOptions();options.fastMathEnabled=false
        let library=try device.makeLibrary(source:source,options:options)
        guard let function=library.makeFunction(name:name) else{throw problem("The Metal function was not found")}
        let pipeline=try device.makeComputePipelineState(function:function)
        guard let queue=device.makeCommandQueue(),let command=queue.makeCommandBuffer(),let encoder=command.makeComputeCommandEncoder(),let result=device.makeBuffer(length:count*MemoryLayout<Float>.stride,options:.storageModeShared) else{throw problem("Metal could not allocate this command")}
        var buffers=[MTLBuffer]()
        for input in inputs {
            let values=input.map{$0.floatValue}
            let buffer:MTLBuffer?=values.withUnsafeBytes{device.makeBuffer(bytes:$0.baseAddress!,length:$0.count,options:.storageModeShared)}
            guard let buffer else{throw problem("Metal could not allocate an input buffer")};buffers.append(buffer)
        }
        memset(result.contents(),0,result.length)
        encoder.setComputePipelineState(pipeline)
        for (i,buffer) in buffers.enumerated(){encoder.setBuffer(buffer,offset:0,index:i)}
        encoder.setBuffer(result,offset:0,index:inputs.count)
        encoder.dispatchThreads(MTLSize(width:count,height:1,depth:1),threadsPerThreadgroup:MTLSize(width:min(256,pipeline.maxTotalThreadsPerThreadgroup),height:1,depth:1))
        encoder.endEncoding();command.commit();command.waitUntilCompleted()
        guard command.status == .completed else{throw command.error ?? problem("The GPU did not complete this kernel")}
        let values=Array(UnsafeBufferPointer(start:result.contents().assumingMemoryBound(to:Float.self),count:count))
        return ["value":values,"device":device.name,"backend":"Metal source kernel","local":true,"seconds":Date().timeIntervalSince(started)]
    }
    private static func problem(_ message:String)->NSError{NSError(domain:"VaultLabGPU",code:1,userInfo:[NSLocalizedDescriptionKey:message])}
    private static func encode(_ value:[String:Any])->String {
        guard let data=try? JSONSerialization.data(withJSONObject:value,options:[.fragmentsAllowed]) else{return "{\"error\":\"GPU produced non-finite values\"}"}
        return String(decoding:data,as:UTF8.self)
    }
}
