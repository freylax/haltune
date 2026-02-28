# tests/lib/test_bridge_client.py
import pytest
from lib.bridge_client import BridgeClient, BridgeResponse

def test_send_request_returns_bridge_response():
    client = BridgeClient(host="localhost", port=8765, timeout=5.0)
    response = client.send_request({"type": "ping"})
    assert isinstance(response, BridgeResponse)
    # Response may indicate server not available - that's ok for this test
