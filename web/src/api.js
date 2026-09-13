export async function api(method,args={}) {
 if(!window.webkit?.messageHandlers?.vault) throw new Error('Open this library in the Vault app.');
 return window.webkit.messageHandlers.vault.postMessage({method,args});
}
export const assetURL = path => 'vault://document/'+path.split('/').map(encodeURIComponent).join('/');
