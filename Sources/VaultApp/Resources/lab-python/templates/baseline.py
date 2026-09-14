#!/usr/bin/env python3
"""Small stdlib-only teaching experiment. Synthetic sequence data, no model load."""
import argparse,hashlib,json,math,pathlib,platform,random,sys

def generate(seed,n):
    rng=random.Random(seed);state=0;observations=[]
    for t in range(n+1):
        if rng.random() < (0.08 if t < int(n*0.7) else 0.28):state=1-state
        observations.append(state if rng.random()>0.1 else 1-state)
    return [{'id':t,'time':t,'observation':observations[t],'target':observations[t+1]} for t in range(n)]

def fit(rows):
    counts=[[1,1],[1,1]]
    for r in rows:counts[r['observation']][r['target']]+=1
    return {'constant':(1+sum(r['target'] for r in rows))/(2+len(rows)),
            'transition':[c[1]/sum(c) for c in counts]}

def score(rows,model,kind):
    ps=[model['constant'] if kind=='constant' else model['transition'][r['observation']] for r in rows]
    return {'examples':len(rows),'accuracy':sum(int(p>=0.5)==r['target'] for p,r in zip(ps,rows))/len(rows),
            'brier':sum((p-r['target'])**2 for p,r in zip(ps,rows))/len(rows),
            'negative_log_likelihood_nats':-sum(r['target']*math.log(p)+(1-r['target'])*math.log1p(-p) for p,r in zip(ps,rows))/len(rows)}

def self_check():
    rows=[{'observation':0,'target':0},{'observation':0,'target':1},{'observation':1,'target':1}]
    m=fit(rows);assert m['constant']==3/5 and m['transition']==[1/2,2/3]
    assert generate(7,100)==generate(7,100)
    assert generate(7,100)!=generate(8,100)
    fixture=generate(7,100);assert all(a['target']==b['observation'] for a,b in zip(fixture,fixture[1:]))
    before=json.dumps(m,sort_keys=True);metrics=score(rows,m,'transition');assert before==json.dumps(m,sort_keys=True) and 0<=metrics['accuracy']<=1
    return {'checks':5,'passed':True}

def main():
    ap=argparse.ArgumentParser();ap.add_argument('--out',type=pathlib.Path);ap.add_argument('--seed',type=int,default=7);ap.add_argument('--events',type=int,default=800);ap.add_argument('--self-check',action='store_true');args=ap.parse_args()
    if args.self_check:print(json.dumps(self_check()));return
    if args.out is None or not 100<=args.events<=10000:ap.error('--out is required; --events must be between 100 and 10000')
    out=args.out.resolve();out.mkdir(parents=True,exist_ok=True)
    if any(out.iterdir()):raise SystemExit('Refusing to overwrite a nonempty run directory; choose a new --out.')
    rows=generate(args.seed,args.events);a=int(len(rows)*.6);b=int(len(rows)*.8)
    # One-event gaps avoid sharing boundary observations between adjacent splits.
    splits={'train':rows[:a-1],'validation':rows[a:b-1],'test':rows[b:]}
    model=fit(splits['train'])
    metrics={part:{kind:score(rs,model,kind) for kind in ['constant','transition']} for part,rs in splits.items()}
    chosen=min(metrics['validation'],key=lambda k:metrics['validation'][k]['negative_log_likelihood_nats'])
    raw=''.join(json.dumps(r,sort_keys=True)+'\n' for r in rows);(out/'events.jsonl').write_text(raw)
    manifest={'kind':'synthetic educational baseline; no neural or person-model evidence','seed':args.seed,'events':args.events,'data_sha256':hashlib.sha256(raw.encode()).hexdigest(),'code_sha256':hashlib.sha256(pathlib.Path(__file__).read_bytes()).hexdigest(),'python':sys.version,'platform':platform.platform(),'split_ids':{p:[r['id'] for r in rs] for p,rs in splits.items()},'omitted_boundary_ids':[a-1,b-1],'selection_metric':'validation negative log likelihood','selected_model':chosen,'fitted_on':'train only'}
    for name,obj in [('manifest',manifest),('model',model),('metrics',metrics)]:
        (out/(name+'.json')).write_text(json.dumps(obj,indent=2)+'\n')
    print(json.dumps({'out':str(out),'selected_model':chosen,'test':metrics['test'][chosen],'self_check':self_check()},indent=2))

if __name__=='__main__':main()
