export function chooseModel(models,candidates=[],remoteAllowed=false) {
 const available=new Set(models.map(model=>model.id));
 const selected=candidates.find(id=>id&&(available.has(id)||(remoteAllowed&&(id==='paired-mac'||id.startsWith('remote/')))));
 return selected||models.find(model=>model.recommended)?.id||models.find(model=>model.id.includes('Qwen3.5'))?.id||models[0]?.id||(remoteAllowed?'paired-mac':'');
}
