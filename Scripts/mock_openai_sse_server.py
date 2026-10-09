#!/usr/bin/env python3
"""Loopback-only OpenAI-compatible streaming fixture for the Pi RPC test."""

from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import sys
import time


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        request = json.loads(self.rfile.read(length))
        if self.path != "/v1/chat/completions" or self.headers.get("Authorization") != "Bearer openmuse-test-token":
            self.send_error(401)
            return
        if not request.get("stream"):
            self.send_error(400, "This fixture only supports streaming requests")
            return

        now = int(time.time())
        events = [
            {
                "id": "openmuse-local-test",
                "object": "chat.completion.chunk",
                "created": now,
                "model": request.get("model", "demo-model"),
                "choices": [{"index": 0, "delta": {"role": "assistant", "content": "Pi RPC 本地模拟模型验证成功。"}, "finish_reason": None}],
            },
            {
                "id": "openmuse-local-test",
                "object": "chat.completion.chunk",
                "created": now,
                "model": request.get("model", "demo-model"),
                "choices": [{"index": 0, "delta": {}, "finish_reason": "stop"}],
            },
        ]
        payload = b"".join(b"data: " + json.dumps(event, ensure_ascii=False).encode() + b"\n\n" for event in events)
        payload += b"data: [DONE]\n\n"
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *_):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 19876
    print(f"OpenMuse test fixture listening on http://127.0.0.1:{port}/v1", flush=True)
    ThreadingHTTPServer(("127.0.0.1", port), Handler).serve_forever()
