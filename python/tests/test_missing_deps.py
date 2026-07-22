import builtins
import pytest


# @pytest.mark.parametrize("missing", ["nbformat"])
# def test_missing_optional_dependency(monkeypatch, missing):
#     real_import = builtins.__import__
#
#     def fake_import(name, *args, **kwargs):
#         if name == missing:
#             raise ModuleNotFoundError(name)
#         return real_import(name, *args, **kwargs)
#
#     monkeypatch.setattr(builtins, "__import__", fake_import)
#
#     from kernel.kernel_manager import KernelManager
#
#     assert getattr(KernelManager, missing) is None
