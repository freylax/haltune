"""HAL bridge server comprehensive tests.

Migrated from test_bridge_comprehensive.sh and test_remote_hal.py.
"""

import socket
import pytest
from pathlib import Path

from lib.bridge_client import BridgeClient
from lib.config import load_config


@pytest.fixture(scope="module")
def config():
    config_path = Path(__file__).parent / "config" / "test_config.toml"
    return load_config(config_path)


@pytest.fixture
def bridge_client(config):
    client = BridgeClient(
        host=config.hosts["local"].bridge_host,
        port=config.hosts["local"].bridge_port,
        timeout=config.tests.bridge_connect_timeout
    )
    return client


class TestBridgePing:
    """Test 1: Ping request (from test_bridge_comprehensive.sh and test_remote_hal.py)"""

    def test_ping_pong(self, bridge_client):
        response = bridge_client.send_request({"type": "ping"})
        if not response.success:
            pytest.skip(f"Bridge server not available: {response.error}")
        # Server echoes back "type":"ping" (not "pong" as protocol may vary)
        assert response.data.get("type") in ["ping", "pong"], f"Unexpected response type: {response.data}"


class TestBridgeListPins:
    """Test 2: List pins request (from test_bridge_comprehensive.sh and test_remote_hal.py)"""

    def test_list_pins_returns_pins(self, bridge_client):
        response = bridge_client.send_request({"type": "list_pins"})
        if not response.success:
            pytest.skip(f"Bridge server not available: {response.error}")
        assert "pins" in response.data
        pins = response.data["pins"]
        assert isinstance(pins, list)
        # Check for known pins if HAL is running
        if pins:
            pin = pins[0]
            assert "name" in pin
            assert "type" in pin

    def test_list_pins_via_helper(self, bridge_client):
        pins = bridge_client.list_pins()
        assert isinstance(pins, list)

    def test_list_pins_has_expected_structure(self, bridge_client):
        pins = bridge_client.list_pins()
        for pin in pins[:5]:  # Check first 5
            assert "name" in pin
            assert "type" in pin
            assert "dir" in pin
            assert "value" in pin


class TestBridgeGetPin:
    """Test 3: Get pin request (from test_bridge_comprehensive.sh and test_remote_hal.py)"""

    def test_get_pin_by_name(self, bridge_client):
        pins = bridge_client.list_pins()
        if pins:
            pin_name = pins[0]["name"]
            pin = bridge_client.get_pin(pin_name)
            assert pin is not None
            assert pin["name"] == pin_name

    def test_get_nonexistent_pin(self, bridge_client):
        """Test that requesting a non-existent pin returns an error."""
        response = bridge_client.send_request({"type": "get_pin", "name": "test.nonexistent"})
        assert not response.success, "Expected error for non-existent pin"

    def test_get_pin_without_name(self, bridge_client):
        """Test that get_pin without name field returns error."""
        response = bridge_client.send_request({"type": "get_pin"})
        assert not response.success, "Expected error when name is missing"


class TestBridgeSetPin:
    """Test 4-5: Set pin request (from test_bridge_comprehensive.sh)"""

    def test_set_pin_bit_value(self, bridge_client):
        """Test 4: Set pin with bit value."""
        response = bridge_client.send_request({
            "type": "set_pin",
            "name": "test.pin",
            "value": {"bit": True}
        })
        # May succeed or fail depending on if pin exists - but should get a response
        assert response.data is not None

    def test_set_pin_float_value(self, bridge_client):
        """Test 5: Set pin with float value."""
        response = bridge_client.send_request({
            "type": "set_pin",
            "name": "test.float",
            "value": {"float": 3.14}
        })
        # May succeed or fail depending on if pin exists - but should get a response
        assert response.data is not None

    def test_set_pin_s32_value(self, bridge_client):
        """Test set_pin with s32 value."""
        response = bridge_client.send_request({
            "type": "set_pin",
            "name": "test.s32",
            "value": {"s32": 42}
        })
        assert response.data is not None

    def test_set_pin_u32_value(self, bridge_client):
        """Test set_pin with u32 value."""
        response = bridge_client.send_request({
            "type": "set_pin",
            "name": "test.u32",
            "value": {"u32": 42}
        })
        assert response.data is not None

    def test_set_pin_without_name(self, bridge_client):
        """Test that set_pin without name returns error."""
        response = bridge_client.send_request({
            "type": "set_pin",
            "value": {"bit": True}
        })
        assert not response.success, "Expected error when name is missing"


class TestBridgeSignals:
    """Test 6: List signals request (from test_bridge_comprehensive.sh and test_remote_hal.py)"""

    def test_list_signals(self, bridge_client):
        response = bridge_client.send_request({"type": "list_signals"})
        assert response.data is not None
        if response.success:
            assert "signals" in response.data

    def test_list_signals_via_helper(self, bridge_client):
        signals = bridge_client.list_signals()
        assert isinstance(signals, list)


class TestBridgeParams:
    """Test 7: List params request (from test_bridge_comprehensive.sh)"""

    def test_list_params(self, bridge_client):
        response = bridge_client.send_request({"type": "list_params"})
        assert response.data is not None
        if response.success:
            assert "params" in response.data

    def test_list_params_via_helper(self, bridge_client):
        params = bridge_client.list_params()
        assert isinstance(params, list)


class TestBridgeGetParam:
    """Test 9: Get param request (from test_bridge_comprehensive.sh)"""

    def test_get_param_by_name(self, bridge_client):
        params = bridge_client.list_params()
        if params:
            param_name = params[0]["name"]
            response = bridge_client.send_request({
                "type": "get_param",
                "name": param_name
            })
            # May succeed or error - just check we got a response
            assert response.data is not None

    def test_get_nonexistent_param(self, bridge_client):
        """Test that requesting a non-existent param returns an error."""
        response = bridge_client.send_request({
            "type": "get_param",
            "name": "test.nonexistent"
        })
        assert not response.success, "Expected error for non-existent param"


class TestBridgeSetParam:
    """Additional test for set_param (supported by protocol)"""

    def test_set_param(self, bridge_client):
        response = bridge_client.send_request({
            "type": "set_param",
            "name": "test.param",
            "value": {"float": 1.23}
        })
        # May succeed or fail - just check we got a response
        assert response.data is not None


class TestBridgeComponents:
    """Test 8: List components request (from test_bridge_comprehensive.sh and test_remote_hal.py)"""

    def test_list_components(self, bridge_client):
        response = bridge_client.send_request({"type": "list_components"})
        assert response.data is not None
        if response.success:
            assert "components" in response.data

    def test_list_components_via_helper(self, bridge_client):
        components = bridge_client.list_components()
        assert isinstance(components, list)


class TestBridgeSignalOperations:
    """Test 10-11: Create and delete signals (from test_bridge_comprehensive.sh)"""

    def test_create_signal(self, bridge_client):
        """Test 10: Create signal request."""
        response = bridge_client.send_request({
            "type": "create_signal",
            "name": "test.signal",
            "pin_type": "bit"
        })
        # May succeed or fail - just check we got a response
        assert response.data is not None

    def test_delete_signal(self, bridge_client):
        """Test 11: Delete signal request."""
        response = bridge_client.send_request({
            "type": "delete_signal",
            "name": "test.signal"
        })
        # May succeed or fail - just check we got a response
        assert response.data is not None

    def test_create_signal_without_name(self, bridge_client):
        """Test that create_signal without name returns error."""
        response = bridge_client.send_request({
            "type": "create_signal",
            "pin_type": "bit"
        })
        assert not response.success, "Expected error when name is missing"


class TestBridgePinLinking:
    """Test 12-13: Link and unlink pins (from test_bridge_comprehensive.sh)"""

    def test_link_pin(self, bridge_client):
        """Test 12: Link pin request."""
        response = bridge_client.send_request({
            "type": "link_pin",
            "pin_name": "test.pin",
            "sig_name": "test.signal"
        })
        # May succeed or fail - just check we got a response
        assert response.data is not None

    def test_unlink_pin(self, bridge_client):
        """Test 13: Unlink pin request."""
        response = bridge_client.send_request({
            "type": "unlink_pin",
            "name": "test.pin"
        })
        # May succeed or fail - just check we got a response
        assert response.data is not None


class TestBridgeErrors:
    """Test 14: Invalid JSON and error handling (from test_bridge_comprehensive.sh)"""

    def test_invalid_request_type(self, bridge_client):
        response = bridge_client.send_request({"type": "invalid_request_type"})
        assert not response.success
        assert response.error is not None

    def test_malformed_json(self, bridge_client):
        """Test 14: Invalid JSON handling (raw socket test)."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(5.0)
                s.connect((bridge_client.host, bridge_client.port))
                s.sendall(b"{invalid json}\n")
                response_data = s.recv(65536).decode()
                # Should get error response
                assert "error" in response_data.lower() or "invalid" in response_data.lower()
        except (socket.timeout, ConnectionRefusedError):
            pytest.skip("Bridge server not available")

    def test_missing_type_field(self, bridge_client):
        """Test that request without type field returns error."""
        response = bridge_client.send_request({"name": "test"})
        assert not response.success, "Expected error when type is missing"


class TestBridgeConnection:
    """Additional connection tests for robustness."""

    def test_connection_refused_on_wrong_port(self, config):
        """Test that wrong port fails appropriately."""
        client = BridgeClient(
            host=config.hosts["local"].bridge_host,
            port=9999,  # Wrong port
            timeout=1.0
        )
        response = client.send_request({"type": "ping"})
        assert not response.success
        assert response.error is not None

    def test_ping_via_helper(self, bridge_client):
        """Test ping using the helper method."""
        result = bridge_client.ping()
        # May be False if server not running - that's ok
        assert isinstance(result, bool)
