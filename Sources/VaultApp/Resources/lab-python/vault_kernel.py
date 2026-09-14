"""Embedded notebook/project kernel. Ordinary .py/.ipynb files remain portable."""
import ast, base64, contextlib, hashlib, importlib, io, json, os, pathlib, shlex
import sys, time, traceback, uuid

_sessions = {}
_project_modules = {}
_outputs = None
_limit = 1_000_000

class Capture(io.StringIO):
    def write(self, text):
        remaining = _limit - self.tell()
        if remaining > 0: super().write(str(text)[:remaining])
        return len(text)

def safe(root, relative):
    root = pathlib.Path(root).resolve()
    p = root / relative
    if pathlib.Path(relative).is_absolute() or '..' in pathlib.PurePath(relative).parts:
        raise ValueError('Use a path within this project')
    for parent in [p, *p.parents]:
        if parent == root: break
        if parent.is_symlink(): raise ValueError('Symbolic links are not supported in the lab')
    p = p.resolve()
    if not p.is_relative_to(root): raise ValueError('This file is outside the project')
    return p

def atomic(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + '.saving-' + uuid.uuid4().hex)
    try:
        temporary.write_text(text, encoding='utf-8')
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)

def digest(text): return hashlib.sha256(text.encode()).hexdigest()

def file_digest(path):
    with path.open('rb') as f: return hashlib.file_digest(f,'sha256').hexdigest()

def display(value):
    if _outputs is None: return
    data = {'text/plain': repr(value)[:20000]}
    if hasattr(value, '_repr_html_'):
        html = value._repr_html_()
        if html: data['text/html'] = str(html)[:300000]
    _outputs.append({'output_type': 'display_data', 'data': data, 'metadata': {}})

def capture_figures():
    if _outputs is None or 'matplotlib.pyplot' not in sys.modules: return
    plt=sys.modules['matplotlib.pyplot']
    for num in plt.get_fignums():
        f=plt.figure(num);b=io.BytesIO();f.savefig(b,format='png',dpi=140,bbox_inches='tight')
        if b.tell()<=8_000_000:
            _outputs.append({'output_type':'display_data','data':{'image/png':base64.b64encode(b.getvalue()).decode()},'metadata':{}})
    plt.close('all')

def notebook(cells):
    return {'nbformat':4,'nbformat_minor':5,'metadata':{'kernelspec':{'display_name':'Python · Vault','language':'python','name':'python3'},'language_info':{'name':'python','version':'.'.join(map(str,sys.version_info[:3]))}},
            'cells':[{'cell_type':kind,'id':uuid.uuid4().hex[:12],'metadata':{},'source':text.splitlines(True),**({'execution_count':None,'outputs':[]} if kind=='code' else {})} for kind,text in cells]}

def seed_project(root, name='First experiment'):
    project = safe(root, name)
    if project.exists(): return project
    project.mkdir(parents=True)
    templates = pathlib.Path(__file__).parent/'templates'
    for p in templates.iterdir():
        if p.is_file(): (project/p.name).write_bytes(p.read_bytes())
    return project

def project_directory(vault, name):
    if name.startswith('@/'):
        return safe(vault, name[2:])
    if not name or '/' in name or name.startswith('.'):
        raise ValueError('Choose a project inside this vault')
    return safe(vault,'Labs/'+name)

def recent_projects(vault, name=None):
    path=safe(vault,'.archii-vault/lab-recents.json')
    try: rows=json.loads(path.read_text(encoding='utf-8'))
    except (OSError, ValueError): rows=[]
    if name and name.startswith('@/') and (not rows or rows[0]!=name):
        rows=[name,*[p for p in rows if p!=name]][:12];atomic(path,json.dumps(rows))
    return [p for p in rows if isinstance(p,str) and p.startswith('@/') and project_directory(vault,p).is_dir()]

def listing(project):
    result=[]
    for base, dirs, files in os.walk(project):
        dirs[:] = sorted((d for d in dirs if not d.startswith('.') and d not in ['__pycache__','site-packages','node_modules','venv','env','target','dist','build','coverage','DerivedData','Pods','Carthage'] and not (pathlib.Path(base)/d).is_symlink()),key=lambda d:(d=='runs',d)) if len(pathlib.Path(base).relative_to(project).parts)<4 else []
        for name in sorted(files):
            p=pathlib.Path(base)/name
            if name.startswith('.') or p.is_symlink(): continue
            rel=str(p.relative_to(project))
            if len(pathlib.Path(rel).parts)>5: continue
            result.append({'path':rel,'name':name,'size':p.stat().st_size,'ext':p.suffix[1:]})
            if len(result)>=500: return result
    return result

def variables(ns):
    result=[]
    for name,value in ns.items():
        if name.startswith('_') or isinstance(value,type(sys)): continue
        kind=type(value).__name__
        if hasattr(value,'shape'):summary=str(value.shape)+' · '+str(getattr(value,'dtype',kind))
        elif callable(value):summary='function' if hasattr(value,'__code__') else kind
        else:
            try:summary=repr(value)[:130]
            except Exception:summary=kind
        result.append({'name':name,'type':kind,'value':summary})
    return result[-60:]

def run_code(project, code, filename, timeout=120, mode='cell', execution='embedded-local'):
    global _outputs
    import _vault_native
    key=str(project)
    ns=_sessions.setdefault(key,{'__name__':'__main__','__builtins__':__builtins__})
    outputs=[];_outputs=outputs
    stdout,stderr=Capture(),Capture()
    start=time.monotonic();run_id=time.strftime('%Y%m%d-%H%M%S')+'-'+uuid.uuid4().hex[:8]
    previous_dir=os.getcwd();previous_path=list(sys.path);previous_argv=list(sys.argv)
    old_trace=sys.gettrace()
    count=0
    def trace(frame,event,arg):
        nonlocal count
        count+=1
        if count%64==0:
            if _vault_native.cancelled(): raise KeyboardInterrupt('Stopped by you')
            if time.monotonic()-start>timeout: raise TimeoutError(f'This run exceeded its {timeout}-second budget')
        return trace
    status='ok';error=None
    try:
        os.chdir(project)
        sys.path.insert(0,str(project));sys.path.insert(0,str(project/'.vaultlab'/'packages'))
        sys.modules.update(_project_modules.get(key, {}))
        importlib.invalidate_caches()
        with contextlib.redirect_stdout(stdout),contextlib.redirect_stderr(stderr):
            sys.settrace(trace)
            if mode=='console':
                command=shlex.split(code)
                if not command: pass
                elif command[0] in ('python','python3','run'):
                    if len(command)<2:raise ValueError('Usage: python filename.py [arguments]')
                    p=safe(project,command[1]);sys.argv=[str(p),*command[2:]]
                    ns['__file__']=str(p);exec(compile(p.read_text(encoding='utf-8'),str(p),'exec'),ns)
                elif command[0]=='pytest':
                    import pytest
                    rc=pytest.main(command[1:] or ['-q'])
                    if int(rc):raise RuntimeError(f'pytest exited with status {int(rc)}')
                elif command[0]=='pip':
                    if len(command)<3 or command[1]!='install' or any(x.startswith('-') for x in command[2:]):
                        raise ValueError('Use pip install package-name. Only pure Python wheels can be added on-device.')
                    from pip._internal.cli.main import main
                    site=project/'.vaultlab'/'packages'
                    rc=main(['install','--target',str(site),'--only-binary=:all:','--platform','any','--implementation','py','--abi','none','--disable-pip-version-check','--no-compile',*command[2:]])
                    if rc:raise RuntimeError('Package installation failed; native extensions must be bundled for iPad')
                elif command[0]=='git': git_command(project,command[1:])
                elif command[0]=='pwd': print(project)
                elif command[0]=='ls':
                    p=safe(project,command[1] if len(command)>1 else '')
                    print('\n'.join(x.name+('/' if x.is_dir() else '') for x in sorted(p.iterdir()) if not x.name.startswith('.')))
                elif command[0]=='cat': print(safe(project,command[1]).read_text(encoding='utf-8'))
                elif command[0]=='help':print('python file.py [args] · pytest -q · pip install package · git init/status/add/commit/log/diff · ls · pwd · cat file\nThis console runs embedded tools on this device; it is not a Unix process shell.')
                else: execute_cell(code,filename,ns)
            else: execute_cell(code,filename,ns)
            capture_figures()
    except BaseException as exc:
        if isinstance(exc,SystemExit) and exc.code in (None,0):pass
        else:
            status='interrupted' if isinstance(exc,(KeyboardInterrupt,TimeoutError)) else 'error'
            error={'output_type':'error','ename':type(exc).__name__,'evalue':str(exc),'traceback':traceback.format_exception(exc)}
    finally:
        sys.settrace(old_trace)
        if 'matplotlib.pyplot' in sys.modules: sys.modules['matplotlib.pyplot'].close('all')
        local_modules = {}
        for name, module in list(sys.modules.items()):
            location = getattr(module, '__file__', None)
            if location:
                try:
                    if pathlib.Path(location).resolve().is_relative_to(project):
                        local_modules[name] = module
                        sys.modules.pop(name, None)
                except (OSError, ValueError): pass
        _project_modules[key] = local_modules
        os.chdir(previous_dir);sys.path[:]=previous_path;sys.argv=previous_argv;_outputs=None
    streams=[]
    if stdout.getvalue():streams.append({'output_type':'stream','name':'stdout','text':stdout.getvalue()})
    if stderr.getvalue():streams.append({'output_type':'stream','name':'stderr','text':stderr.getvalue()})
    outputs=streams+outputs+([error] if error else [])
    elapsed=round(time.monotonic()-start,3)
    record={'id':run_id,'status':status,'seconds':elapsed,'file':filename,'code_sha256':digest(code),'code':code,'python':sys.version,'platform':sys.platform,'execution':execution,'outputs':outputs}
    atomic(project/'runs'/run_id/'record.json',json.dumps(record,indent=2,default=str))
    return {**record,'variables':variables(ns),'files':listing(project)}

def execute_cell(code,filename,ns):
    tree=ast.parse(code,filename=filename,mode='exec')
    if tree.body and isinstance(tree.body[-1],ast.Expr):
        last=tree.body.pop()
        exec(compile(tree,filename,'exec'),ns)
        value=eval(compile(ast.Expression(last.value),filename,'eval'),ns)
        if value is not None:
            ns['_']=value;display(value)
    else:exec(compile(tree,filename,'exec'),ns)

def git_command(project,args):
    from dulwich import porcelain
    if not args:raise ValueError('Use git init, status, add, commit, log, or diff')
    command=args[0]
    if command=='init':porcelain.init(str(project));print('Initialized Git repository')
    elif command=='status':
        s=porcelain.status(str(project));print('Staged:',s.staged,'\nUnstaged:',s.unstaged,'\nUntracked:',s.untracked)
    elif command=='add':
        paths=args[1:] or ['.']
        if paths==['.']: paths=[str(project/f['path']) for f in listing(project) if not f['path'].startswith('runs/')]
        else:paths=[str(safe(project,p)) for p in paths]
        porcelain.add(str(project),paths=paths);print('Changes staged')
    elif command=='commit':
        if len(args)<3 or args[1]!='-m':raise ValueError('Use git commit -m "message"')
        ident=b'Vault Lab <local@vault>'
        print(porcelain.commit(str(project),message=args[2].encode(),author=ident,committer=ident).decode())
    elif command=='log':porcelain.log(str(project),outstream=sys.stdout,max_entries=8)
    elif command=='diff':
        b=io.BytesIO();porcelain.diff(str(project),outstream=b);print(b.getvalue().decode(errors='replace'))
    else:raise ValueError('Supported Git commands: init, status, add, commit, log, diff')

def dispatch_json(payload):
    try:return json.dumps(dispatch(json.loads(payload)),default=str,allow_nan=False)
    except BaseException as exc:return json.dumps({'error':str(exc),'type':type(exc).__name__})

def dispatch(request):
    args=request.get('args',{});method=request['method']
    root=safe(request['root'],'Labs');root.mkdir(parents=True,exist_ok=True)
    os.environ['MPLBACKEND']='module://vault_backend'
    config=root/'.vaultlab'/'matplotlib';config.mkdir(parents=True,exist_ok=True);os.environ['MPLCONFIGDIR']=str(config)
    if method=='labProjects':
        seed_project(root)
        return {'projects':[{'name':p,'title':pathlib.Path(p[2:]).name or 'Vault','files':len(listing(project_directory(request['root'],p)))} for p in recent_projects(request['root'])]+[{'name':p.name,'files':len(listing(p))} for p in sorted(root.iterdir()) if p.is_dir() and not p.name.startswith('.') and not p.is_symlink()],'root':str(root),'local':True,'python':sys.version.split()[0],'deviceLabel':'This Mac' if request.get('platform')=='mac' else request.get('deviceLabel','This iPad')}
    if method=='labCreateProject':
        name=args.get('name','').strip()
        if not name or '/' in name or name.startswith('.'):raise ValueError('Choose a simple project name')
        p=safe(root,name)
        if p.exists():raise ValueError('A project already has that name')
        if args.get('template',True):seed_project(root,name)
        else:
            p.mkdir();atomic(p/'Untitled.ipynb',json.dumps(notebook([('markdown','# A new question\n\nWhat will you discover?'),('code','print("Hello, Vault.")')]),indent=2))
        return {'name':name}
    project=project_directory(request['root'],args.get('project','First experiment'))
    if not project.is_dir():raise ValueError('Open a project first')
    if method=='labManifest':
        return {'files':[{'path':f['path'],'sha256':file_digest(safe(project,f['path']))} for f in listing(project) if not f['path'].startswith('runs/') and not f['path'].endswith('.ipynb')]}
    if method=='labFiles':
        recent_projects(request['root'],args.get('project'));return {'files':listing(project)}
    if method=='labFileRevision':return {'revision':file_digest(safe(project,args['path']))}
    if method=='labRead':
        p=safe(project,args['path'])
        if p.stat().st_size>16*1024*1024:raise ValueError('This file exceeds the editor’s 16 MiB limit')
        if p.suffix.lower() in ('.png','.jpg','.jpeg','.npz','.npy','.pdf','.zip','.sqlite','.db'):
            data=p.read_bytes()
            return {'path':args['path'],'kind':'image' if p.suffix.lower() in ('.png','.jpg','.jpeg') else 'binary','size':len(data),'sha256':hashlib.sha256(data).hexdigest(),**({'image':'data:image/'+('png' if p.suffix.lower()=='.png' else 'jpeg')+';base64,'+base64.b64encode(data).decode()} if p.suffix.lower() in ('.png','.jpg','.jpeg') else {})}
        text=p.read_text(encoding='utf-8');return {'path':args['path'],'content':text,'revision':digest(text)}
    if method=='labSave':
        p=safe(project,args['path']);content=args['content']
        if not isinstance(content,str) or len(content.encode())>16*1024*1024:raise ValueError('File is too large')
        revision=args.get('revision')
        if p.exists() and (revision is None or digest(p.read_text(encoding='utf-8'))!=revision):raise ValueError('This file changed since you opened it. Reopen it or save a new copy.')
        atomic(p,content);return {'revision':digest(content),'files':listing(project)}
    if method=='labRun':
        return run_code(project,args.get('code',''),args.get('path','<notebook>'),min(max(int(args.get('timeout',120)),1),600),args.get('mode','cell'),args.get('execution','mac-local' if request.get('platform')=='mac' else 'embedded-local'))
    if method=='labReset':
        _sessions.pop(str(project),None)
        _project_modules.pop(str(project),None)
        return {'variables':[],'message':'User variables cleared. Imported packages remain loaded.'}
    if method=='labPackages':
        from importlib.metadata import distributions
        rows=sorted({(d.metadata['Name'],d.version) for d in distributions(path=[*sys.path,str(project/'.vaultlab'/'packages')]) if d.metadata['Name']})
        return {'packages':[{'name':n,'version':v} for n,v in rows],'python':sys.version.split()[0]}
    raise ValueError('Unknown lab operation')
