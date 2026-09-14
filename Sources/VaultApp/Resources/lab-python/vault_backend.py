"""Matplotlib notebook display backend for the embedded Vault kernel."""
from matplotlib.backends.backend_agg import FigureCanvasAgg
from matplotlib.backend_bases import _Backend, FigureManagerBase
@_Backend.export
class _BackendVault(_Backend):
    FigureCanvas = FigureCanvasAgg
    FigureManager = FigureManagerBase
    @staticmethod
    def show(block=None):
        from vault_kernel import capture_figures
        capture_figures()
