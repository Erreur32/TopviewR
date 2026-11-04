"""Minimal ttyd WebSocket client (stdlib): connects, opens a terminal, stays N seconds."""
import base64, json, os, socket, sys, time

host, port, user, pw, hold = sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4], float(sys.argv[5])
auth = base64.b64encode(f"{user}:{pw}".encode()).decode()
s = socket.create_connection((host, port), timeout=5)
s.sendall((f"GET /ws HTTP/1.1\r\nHost: {host}:{port}\r\nOrigin: http://{host}:{port}\r\n"
           f"Authorization: Basic {auth}\r\nConnection: Upgrade\r\nUpgrade: websocket\r\n"
           "Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==\r\n"
           "Sec-WebSocket-Protocol: tty\r\n\r\n").encode())
assert b" 101 " in s.recv(4096).split(b"\r\n")[0], "handshake refused"
payload = json.dumps({"AuthToken": auth, "columns": 120, "rows": 40}).encode()
mask = os.urandom(4)
s.sendall(bytes([0x81, 0x80 | len(payload)]) + mask + bytes(b ^ mask[i % 4] for i, b in enumerate(payload)))
time.sleep(hold)
