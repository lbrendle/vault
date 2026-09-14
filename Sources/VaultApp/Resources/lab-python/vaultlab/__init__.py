"""Local tools for inspectable experiments in Vault."""
__all__ = ["metal", "models", "agents", "display"]


def display(value):
    import vault_kernel
    vault_kernel.display(value)
