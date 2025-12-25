import importlib.util

import pytest


RUNTIME_DEPENDENCIES_MISSING = (
    importlib.util.find_spec("qiskit") is None
    or importlib.util.find_spec("qiskit_ibm_runtime") is None
    or importlib.util.find_spec("qiskit_aer") is None
)


@pytest.fixture()
def stub_runtime_service(monkeypatch):
    """Stub QiskitRuntimeService that always returns an Aer simulator backend."""

    from qiskit_aer import AerSimulator
    import qiskit_ibm_runtime

    class _StubRuntimeService:
        last_backend_name: str | None = None

        def __init__(self, **_: object) -> None:
            type(self).last_backend_name = None

        def backend(self, backend_name: str) -> AerSimulator:
            type(self).last_backend_name = backend_name
            return AerSimulator()

    monkeypatch.setattr(qiskit_ibm_runtime, "QiskitRuntimeService", _StubRuntimeService)
    monkeypatch.setenv("SYNQC_QISKIT_RUNTIME_TOKEN", "stub-token")
    monkeypatch.delenv("SYNQC_QISKIT_RUNTIME_CHANNEL", raising=False)
    monkeypatch.delenv("SYNQC_QISKIT_RUNTIME_INSTANCE", raising=False)

    return _StubRuntimeService
