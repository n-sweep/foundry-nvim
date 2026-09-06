import builtins
import importlib
from contextlib import contextmanager

# Usage:
# with simulate_missing("nbformat"):
#     from kernel.kernel_manager import KernelManager
#     assert KernelManager.nbformat is None


@contextmanager
def simulate_missing(name):
    """Simulate a missing package
    """
    real_import = builtins.__import__
    def fake_import(name_, *args, **kwargs):
        if name_ == name:
            raise ModuleNotFoundError(name_)
        return real_import(name_, *args, **kwargs)
    builtins.__import__ = fake_import
    try:
        yield
    finally:
        builtins.__import__ = real_import
