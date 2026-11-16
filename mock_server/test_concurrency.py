import concurrent.futures
import json
import queue
import socket
import threading
import unittest
from urllib.error import HTTPError
from urllib.request import Request, urlopen
from server import create_server


class ConcurrentApiTests(unittest.TestCase):
    def setUp(self):
        self.release = threading.Event()
        self.entered = queue.Queue()
        def wait(vehicle_id, scenario):
            self.entered.put(vehicle_id)
            if not self.release.wait(5):
                raise RuntimeError('test gate not released')
        self.server = create_server(0, command_wait=wait)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'
        self.pool = concurrent.futures.ThreadPoolExecutor(max_workers=8)

    def tearDown(self):
        self.release.set()
        self.pool.shutdown(wait=True)
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def post(self, request_id, vehicle_id='vehicle-1', enabled=True):
        data = dict(requestId=request_id, vehicleId=vehicle_id, enabled=enabled, scenario='success')
        try:
            with urlopen(Request(self.url + '/commands', data=json.dumps(data).encode(), headers={'Content-Type': 'application/json'}), timeout=5) as r:
                return r.status, json.load(r)
        except HTTPError as e:
            try:
                return e.code, json.load(e)
            finally:
                e.close()

    def test_simultaneous_same_id_replays_pending_once(self):
        barrier = threading.Barrier(6)
        def request():
            barrier.wait(timeout=3)
            return self.post('one')
        futures = [self.pool.submit(request) for _ in range(6)]
        self.assertEqual(self.entered.get(timeout=3), 'vehicle-1')
        # Five duplicate requests finish before the single worker is released.
        completions = concurrent.futures.as_completed(futures, timeout=3)
        done = [next(completions) for _ in range(5)]
        for future in done:
            self.assertEqual(future.result()[1]['result'], 'pending')
        self.release.set()
        for f in futures:
            self.assertEqual(f.result()[0], 200)
        state = self.server.state
        self.assertEqual(state.vehicles['vehicle-1']['revision'], 1)
        self.assertFalse(state.pending)
        self.assertEqual(len(state.commands), 1)

    def test_same_vehicle_race_and_different_vehicle_progress(self):
        first = self.pool.submit(self.post, 'a')
        self.entered.get(timeout=3)
        self.assertEqual(self.post('b')[0], 409)
        self.assertEqual(self.post('a', enabled=False)[0], 409)
        second = self.pool.submit(self.post, 'c', 'vehicle-2')
        self.assertEqual(self.entered.get(timeout=3), 'vehicle-2')
        with self.server.state.lock:
            self.assertEqual(self.server.state.pending, {'vehicle-1', 'vehicle-2'})
        self.release.set()
        self.assertEqual(first.result()[1]['result'], 'success')
        self.assertEqual(second.result()[1]['result'], 'success')
        for id in ['vehicle-1', 'vehicle-2']:
            self.assertEqual(self.server.state.vehicles[id]['revision'], 1)
        self.assertFalse(self.server.state.pending)

    def test_disconnect_before_response_does_not_undo_execution(self):
        body = json.dumps(dict(requestId='lost', vehicleId='vehicle-1', enabled=True, scenario='success')).encode()
        connection = socket.create_connection(('127.0.0.1', self.server.server_port))
        connection.sendall(b'POST /commands HTTP/1.1\r\nHost: localhost\r\nContent-Length: ' + str(len(body)).encode() + b'\r\n\r\n' + body)
        self.entered.get(timeout=3)
        connection.close()
        with urlopen(self.url + '/commands/lost') as response:
            self.assertEqual(json.load(response)['result'], 'pending')
        self.release.set()
        state = self.server.state
        with state.changed:
            self.assertTrue(state.changed.wait_for(lambda: not state.pending, timeout=3))
        self.assertEqual(self.post('lost')[1]['result'], 'success')
        self.assertEqual(state.vehicles['vehicle-1']['revision'], 1)

    def test_read_error_recovery_and_unknown_command_after_restart(self):
        self.server.read_error = True
        with self.assertRaises(HTTPError) as e:
            urlopen(self.url + '/vehicles')
        self.assertEqual(e.exception.code, 503)
        e.exception.close()
        self.server.read_error = False
        self.server.state.advance()
        with urlopen(self.url + '/vehicles/vehicle-1') as response:
            self.assertEqual(json.load(response)['revision'], 1)
        self.release.set()
        self.post('old')
        port = self.server.server_port
        self.server.shutdown(); self.server.server_close(); self.thread.join()
        self.server = create_server(port)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        with self.assertRaises(HTTPError) as e:
            urlopen(self.url + '/commands/old')
        self.assertEqual(e.exception.code, 404)
        e.exception.close()

    def test_invalid_json_types_and_missing_resources(self):
        for body in [b'{', b'[]', b'null', b'{}', b'{"requestId": 5}', b'{"requestId":"x","vehicleId":"vehicle-1","enabled":1,"scenario":"success"}']:
            with self.assertRaises(HTTPError) as e:
                urlopen(Request(self.url + '/commands', data=body))
            self.assertEqual(e.exception.code, 400)
            e.exception.close()
        self.assertFalse(self.server.state.commands)
