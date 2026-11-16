"""Local-only FleetBridge mock REST API. Standard library only."""
import argparse
import json
import threading
import time
from datetime import datetime, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote


def now():
    return datetime.now(timezone.utc).isoformat()


class FleetState:
    def __init__(self):
        self.lock = threading.RLock()
        self.commands = {}
        self.pending = set()
        self.vehicles = {
            f'vehicle-{n}': dict(id=f'vehicle-{n}', name=f'차량 {n}',
                model=f'Fleet Model {n}', latitude=37.55+n*.003,
                longitude=126.96+n*.003,
                status=['driving', 'idle', 'offline'][(n-1) % 3],
                battery=95-n*3, updatedAt=now(), refrigerationOn=False, revision=0)
            for n in range(1, 11)
        }

    def advance(self):
        with self.lock:
            for v in self.vehicles.values():
                if v['status'] == 'offline':
                    continue
                if v['status'] == 'driving':
                    v['latitude'] += .0001
                    v['longitude'] += .0001
                v['updatedAt'] = now()
                v['revision'] += 1
                if v['revision'] % 6 == 0:
                    v['status'] = 'idle' if v['status'] == 'driving' else 'driving'
                if v['revision'] % 12 == 0 and v['battery'] > 0:
                    v['battery'] -= 1


class Handler(BaseHTTPRequestHandler):
    def respond(self, code, value):
        body = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        try:
            self.wfile.write(body)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def do_GET(self):
        time.sleep(self.server.read_delay)
        if self.server.read_error:
            self.respond(503, {'error': 'injected_error'})
            return
        state = self.server.state
        with state.lock:
            if self.path == '/vehicles':
                self.respond(200, list(state.vehicles.values()))
            elif self.path.startswith('/commands/'):
                record = state.commands.get(unquote(self.path.removeprefix('/commands/')))
                self.respond(200 if record else 404, record or {'error': 'not_found'})
            elif self.path.startswith('/vehicles/'):
                v = state.vehicles.get(unquote(self.path.removeprefix('/vehicles/')))
                self.respond(200 if v else 404, v or {'error': 'not_found'})
            else:
                self.respond(404, {'error': 'not_found'})

    def do_POST(self):
        if self.path != '/commands':
            self.respond(404, {'error': 'not_found'})
            return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length <= 0 or length > 4096:
                raise ValueError()
            data = json.loads(self.rfile.read(length))
            request_id = data['requestId']
            vehicle_id = data['vehicleId']
            enabled = data['enabled']
            scenario = data['scenario']
            if (not isinstance(request_id, str) or not request_id or len(request_id) > 128
                    or not isinstance(vehicle_id, str) or type(enabled) is not bool
                    or scenario not in ('success', 'failure', 'timeout')):
                raise ValueError()
            payload = dict(vehicleId=vehicle_id, enabled=enabled, scenario=scenario)
        except (ValueError, KeyError, TypeError):
            self.respond(400, {'error': 'invalid_command'})
            return
        state = self.server.state
        with state.lock:
            if request_id in state.commands:
                record = state.commands[request_id]
                if record['payload'] != payload:
                    self.respond(409, {'error': 'request_id_conflict'})
                else:
                    self.respond(200, record)
                return
            vehicle = state.vehicles.get(vehicle_id)
            if vehicle is None or vehicle['status'] == 'offline':
                self.respond(422, {'error': 'unavailable_vehicle'})
                return
            if vehicle_id in state.pending:
                self.respond(409, {'error': 'vehicle_busy'})
                return
            record = dict(requestId=request_id, payload=payload, result='pending')
            state.commands[request_id] = record
            state.pending.add(vehicle_id)
        done = threading.Event()
        def complete():
            try:
                time.sleep(4 if scenario == 'timeout' else 1)
                with state.lock:
                    vehicle = state.vehicles[vehicle_id]
                    if scenario == 'failure' or vehicle['status'] == 'offline':
                        record['result'] = 'failure'
                    else:
                        vehicle['refrigerationOn'] = enabled
                        vehicle['revision'] += 1
                        record['result'] = 'success'
                    state.pending.discard(vehicle_id)
            finally:
                done.set()
        threading.Thread(target=complete, daemon=True).start()
        done.wait()
        with state.lock:
            self.respond(200, record)


def create_server(port=8080, read_delay=0, read_error=False):
    server = ThreadingHTTPServer(('127.0.0.1', port), Handler)
    server.state = FleetState()
    server.read_delay = read_delay
    server.read_error = read_error
    return server


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--read-delay', type=float, default=0)
    parser.add_argument('--read-error', action='store_true')
    args = parser.parse_args()
    if args.read_delay < 0:
        parser.error('read-delay must be nonnegative')
    server = create_server(args.port, args.read_delay, args.read_error)
    stop = threading.Event()
    def tick():
        while not stop.wait(5):
            server.state.advance()
    threading.Thread(target=tick, daemon=True).start()
    print(f'FleetBridge mock: http://127.0.0.1:{server.server_port}', flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()


if __name__ == '__main__':
    main()
