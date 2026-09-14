"""Line-framed worker used only by the explicitly enabled macOS host."""
import json, sys, types, signal
from vaultlab import agents
def shutdown(signum,frame):
    agents.stop()
    raise SystemExit(143)
signal.signal(signal.SIGTERM,shutdown)
writer=sys.stdout
native=types.ModuleType('_vault_native')
native.cancelled=lambda:False
def request(kind,payload):
    writer.write('VAULT_LAB_'+kind+' '+payload+'\n');writer.flush()
    answer=sys.stdin.readline()
    if not answer:raise RuntimeError('The native GPU bridge disconnected')
    return answer
native.gpu=lambda payload:request('GPU',payload)
native.model=lambda payload:request('MODEL',payload)
sys.modules['_vault_native']=native
import vault_kernel
for line in sys.stdin:
    try:response=vault_kernel.dispatch_json(line)
    except BaseException as exc:response=json.dumps({'error':str(exc)})
    writer.write('VAULT_LAB_REPLY '+response+'\n');writer.flush()
