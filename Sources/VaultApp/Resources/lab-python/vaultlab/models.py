"""Use Vault's installed models on this device, with no server or network.

    from vaultlab import models
    print(models.list())
    answer = models.generate("Explain a confidence interval", max_tokens=128)

Models are installed in Vault Settings. Downloads are never triggered by cells.
The model unloads after each call; Vault's memory and GPU admission checks apply.
"""
import builtins
import json
import _vault_native


def _request(payload):
    result = json.loads(_vault_native.model(json.dumps(payload, allow_nan=False)))
    if 'error' in result:
        raise RuntimeError(result['error'])
    return result


def list():
    """Return the same installed local model metadata as Vault's model chooser."""
    return _request({'method': 'list'})['models']


def chat(messages, *, model=None, max_tokens=512, temperature=0.4,
         context_tokens=4096, thinking='off', timeout=120):
    """Return text plus local execution metadata for user/assistant messages."""
    if not isinstance(messages, (tuple, builtins.list)):
        raise TypeError('messages must be a list of user/assistant messages')
    if not messages or any(not isinstance(m, dict) or m.get('role') not in ('user', 'assistant')
                           or not isinstance(m.get('content'), str) for m in messages):
        raise ValueError('Use nonempty user/assistant messages with string content')
    return _request({'method': 'generate', 'history': messages, 'model_id': model or '',
                     'max_tokens': max_tokens, 'temperature': temperature,
                     'context_tokens': context_tokens, 'thinking': thinking, 'timeout': timeout})


def generate(prompt, **options):
    """Generate text locally; omit model to use Vault's selected installed model."""
    if not isinstance(prompt, str) or not prompt.strip():
        raise ValueError('Write a nonempty prompt')
    return chat([{'role': 'user', 'content': prompt}], **options)['text']
