"""Local tools for inspectable experiments in Vault."""
from . import metal


def display(value):
    import vault_kernel
    vault_kernel.display(value)
