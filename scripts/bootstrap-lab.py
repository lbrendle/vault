#!/usr/bin/env python3
"""Fetch the locked native iOS Python/science bundle. No runtime server is used."""
import concurrent.futures, hashlib, json, pathlib, tarfile, urllib.request, zipfile
ROOT=pathlib.Path(__file__).resolve().parents[1]
DEST=ROOT/'native'/'PythonSupport'; CACHE=DEST/'downloads'
CACHE.mkdir(parents=True,exist_ok=True)
records=json.loads((ROOT/'native'/'lab-dependencies.lock.json').read_text())
def download(record):
    p=CACHE/record['url'].rsplit('/',1)[-1]
    if not p.exists():
        partial=p.with_suffix(p.suffix+'.partial')
        urllib.request.urlretrieve(record['url'],partial)
        partial.replace(p)
    if hashlib.sha256(p.read_bytes()).hexdigest()!=record['sha256']:
        raise RuntimeError(f'Checksum mismatch: {p.name}. Remove the cached file before retrying.')
    return p
archive=download(records[0])
if not (DEST/'Python.xcframework').exists():
    with tarfile.open(archive) as t:t.extractall(DEST,filter='data')
def install(record):
    p=download(record);dst=DEST/record['target'];dst.mkdir(exist_ok=True)
    with zipfile.ZipFile(p) as z:
        for entry in z.infolist():
            if entry.filename.startswith('/') or '..' in pathlib.PurePosixPath(entry.filename).parts:raise ValueError('Unsafe wheel path')
        z.extractall(dst)
    print(record['name'],record['target'],flush=True)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
    list(pool.map(install,records[1:]))
(DEST/'manifest.json').write_text(json.dumps(records,indent=2)+'\n')
print('Verified Python and scientific dependencies are ready.')
