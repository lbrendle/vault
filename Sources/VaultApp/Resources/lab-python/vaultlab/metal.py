"""Small editable tensor graphs executed and differentiated by native MLX.

This is Vault's explicit bridge API, not a replacement for the entire mlx package.
All numerical graph operations and their derivatives execute on this device.
"""
import json
import numpy as np
import _vault_native


def info():
    return _request({'method': 'info'})


def _request(payload):
    result = json.loads(_vault_native.gpu(json.dumps(payload, allow_nan=False)))
    if 'error' in result:
        raise RuntimeError(result['error'])
    return result


class Tensor:
    def __init__(self, data=None, *, op='array', inputs=(), shape=None):
        self.op, self.inputs = op, inputs
        self.data = np.asarray(data, dtype=np.float32) if op == 'array' else None
        self.shape = self.data.shape if self.data is not None else tuple(shape)

    def _binary(self, other, op):
        other = array(other)
        shape = np.broadcast_shapes(self.shape, other.shape)
        return Tensor(op=op, inputs=(self, other), shape=shape)

    def __add__(self, other): return self._binary(other, 'add')
    def __radd__(self, other): return array(other) + self
    def __sub__(self, other): return self._binary(other, 'sub')
    def __rsub__(self, other): return array(other) - self
    def __mul__(self, other): return self._binary(other, 'mul')
    def __rmul__(self, other): return array(other) * self
    def __truediv__(self, other): return self._binary(other, 'div')
    def __rtruediv__(self, other): return array(other) / self
    def __neg__(self): return Tensor(op='neg', inputs=(self,), shape=self.shape)
    def __pow__(self, power):
        if power != 2: raise ValueError('This bridge currently supports square only')
        return self * self
    def __matmul__(self, other):
        other = array(other)
        if len(self.shape) != 2 or len(other.shape) != 2 or self.shape[1] != other.shape[0]:
            raise ValueError('matmul requires compatible two-dimensional matrices')
        return Tensor(op='matmul', inputs=(self, other), shape=(self.shape[0], other.shape[1]))
    @property
    def T(self):
        if len(self.shape) != 2: raise ValueError('Transpose requires a matrix')
        return Tensor(op='transpose', inputs=(self,), shape=self.shape[::-1])
    def relu(self): return Tensor(op='relu', inputs=(self,), shape=self.shape)
    def tanh(self): return Tensor(op='tanh', inputs=(self,), shape=self.shape)
    def exp(self): return Tensor(op='exp', inputs=(self,), shape=self.shape)
    def log(self): return Tensor(op='log', inputs=(self,), shape=self.shape)
    def sum(self): return Tensor(op='sum', inputs=(self,), shape=())
    def mean(self): return Tensor(op='mean', inputs=(self,), shape=())
    def numpy(self):
        result = _request(_graph(self, []))
        return np.asarray(result['value'], dtype=np.float32).reshape(self.shape)
    def item(self): return self.numpy().item()


def array(value): return value if isinstance(value, Tensor) else Tensor(value)
def relu(value): return array(value).relu()
def tanh(value): return array(value).tanh()
def mean(value): return array(value).mean()
def exp(value): return array(value).exp()
def log(value): return array(value).log()


def _graph(output, parameters):
    nodes, identities = [], {}
    def visit(tensor):
        identity = id(tensor)
        if identity in identities: return identities[identity]
        inputs = [visit(x) for x in tensor.inputs]
        index = len(nodes)
        identities[identity] = index
        n = {'op': tensor.op, 'inputs': inputs, 'shape': list(tensor.shape)}
        if tensor.data is not None: n['values'] = tensor.data.ravel().tolist()
        nodes.append(n)
        return index
    # Include unused parameters; their gradients must remain zero.
    for p in parameters: visit(p)
    result = visit(output)
    return {'method': 'graph', 'nodes': nodes, 'output': result,
            'parameters': [identities[id(p)] for p in parameters]}


def value_and_grad(function):
    """Differentiate a scalar loss with respect to a list of parameter arrays."""
    def wrapped(parameters, *args, **kwargs):
        tensors = [Tensor(p) for p in parameters]
        loss = array(function(tensors, *args, **kwargs))
        if loss.shape: raise ValueError('The loss must be a scalar')
        result = _request(_graph(loss, tensors))
        gradients = [np.asarray(g, dtype=np.float32).reshape(t.shape)
                     for g, t in zip(result['gradients'], tensors)]
        return float(result['value'][0]), gradients
    return wrapped


def kernel(source, inputs, count, function="compute"):
    """Compile editable Metal source locally. Inputs occupy buffers 0..n-1;
    the float32 output is buffer n. The grid contains exactly count threads.
    Return (NumPy output, receipt). Native GPU dispatch is not preemptible.
    """
    arrays=[np.asarray(x,dtype=np.float32).ravel() for x in inputs]
    if any(len(a)<count for a in arrays):
        raise ValueError('Every input must contain at least count float32 values')
    result=_request({'method':'kernel','source':source,'function':function,'inputs':[x.tolist() for x in arrays],'count':int(count)})
    return np.asarray(result.pop('value'),dtype=np.float32),result
