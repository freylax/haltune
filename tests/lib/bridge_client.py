"""HAL bridge server communication client."""

import socket
import json
from dataclasses import dataclass
from typing import Any, Optional

@dataclass
class BridgeResponse:
    """Response from bridge server."""
    success: bool
    data: dict[str, Any]
    error: Optional[str] = None

class BridgeClient:
    """Client for communicating with HAL bridge server."""

    def __init__(self, host: str, port: int, timeout: float = 5.0):
        self.host = host
        self.port = port
        self.timeout = timeout

    def send_request(self, request: dict[str, Any]) -> BridgeResponse:
        """Send JSON request and parse response."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
                s.settimeout(self.timeout)
                s.connect((self.host, self.port))
                s.sendall(json.dumps(request).encode() + b"\n")
                response_data = s.recv(65536).decode()
                response = json.loads(response_data)

            return BridgeResponse(
                success=response.get("type") != "error",
                data=response,
                error=response.get("error")
            )
        except (socket.timeout, ConnectionRefusedError, json.JSONDecodeError) as e:
            return BridgeResponse(success=False, data={}, error=str(e))

    def ping(self) -> bool:
        """Send ping request."""
        response = self.send_request({"type": "ping"})
        return response.success and response.data.get("type") == "pong"

    def list_pins(self) -> list[dict]:
        """List all HAL pins."""
        response = self.send_request({"type": "list_pins"})
        if response.success:
            return response.data.get("pins", [])
        return []

    def get_pin(self, pin_name: str) -> Optional[dict]:
        """Get specific pin value."""
        response = self.send_request({"type": "get_pin", "name": pin_name})
        if response.success:
            return response.data.get("pin")
        return None

    def set_pin(self, pin_name: str, value: Any) -> BridgeResponse:
        """Set pin value."""
        return self.send_request({
            "type": "set_pin",
            "name": pin_name,
            "value": value
        })

    def list_signals(self) -> list[dict]:
        """List all HAL signals."""
        response = self.send_request({"type": "list_signals"})
        if response.success:
            return response.data.get("signals", [])
        return []

    def list_params(self) -> list[dict]:
        """List all HAL parameters."""
        response = self.send_request({"type": "list_params"})
        if response.success:
            return response.data.get("params", [])
        return []

    def list_components(self) -> list[dict]:
        """List all HAL components."""
        response = self.send_request({"type": "list_components"})
        if response.success:
            return response.data.get("components", [])
        return []
