import json
import threading
import unittest
from urllib.request import urlopen
from urllib.error import HTTPError
from server import create_server


class ReadApiTests(unittest.TestCase):
    def setUp(self):
        self.server = create_server(0)
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.url = f'http://127.0.0.1:{self.server.server_port}'

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join()

    def test_list_detail_missing_and_authoritative_updates(self):
        with urlopen(self.url + '/vehicles') as response:
            vehicles = json.load(response)
        self.assertEqual(len(vehicles), 10)
        self.server.state.advance()
        with urlopen(self.url + '/vehicles/vehicle-1') as response:
            vehicle = json.load(response)
        self.assertEqual(vehicle['revision'], 1)
        self.assertGreater(vehicle['latitude'], vehicles[0]['latitude'])
        with self.assertRaises(HTTPError) as error:
            urlopen(self.url + '/vehicles/missing')
        self.assertEqual(error.exception.code, 404)
        error.exception.close()


class CommandApiTests(ReadApiTests):
    def post(self, data, timeout=6):
        from urllib.request import Request
        with urlopen(Request(self.url + '/commands', data=json.dumps(data).encode(), headers={'Content-Type': 'application/json'}), timeout=timeout) as response:
            return json.load(response)

    def test_duplicate_payload_conflict_and_single_execution(self):
        data = dict(requestId='same', vehicleId='vehicle-1', enabled=True, scenario='success')
        first = []
        thread = threading.Thread(target=lambda: first.append(self.post(data)))
        thread.start()
        import time
        deadline = time.monotonic() + 2
        while 'same' not in self.server.state.commands and time.monotonic() < deadline:
            time.sleep(.01)
        self.assertEqual(self.post(data)['result'], 'pending')
        for invalid in [{**data, 'enabled': False}, {**data, 'requestId': 'other'}]:
            with self.assertRaises(HTTPError) as error:
                self.post(invalid)
            self.assertEqual(error.exception.code, 409)
            error.exception.close()
        thread.join()
        self.assertEqual(first[0]['result'], 'success')
        self.assertEqual(self.post(data)['result'], 'success')
        self.assertEqual(self.server.state.vehicles['vehicle-1']['revision'], 1)

    def test_timeout_does_not_cancel_command_and_offline_is_rejected(self):
        import time
        data = dict(requestId='late', vehicleId='vehicle-1', enabled=True, scenario='timeout')
        with self.assertRaises(TimeoutError):
            self.post(data, timeout=.05)
        time.sleep(4.1)
        with urlopen(self.url + '/commands/late') as response:
            self.assertEqual(json.load(response)['result'], 'success')
        with self.assertRaises(HTTPError) as error:
            self.post({**data, 'requestId': 'offline', 'vehicleId': 'vehicle-3'})
        self.assertEqual(error.exception.code, 422)
        error.exception.close()
        self.assertEqual(self.post({**data, 'requestId': 'fail', 'scenario': 'failure'})['result'], 'failure')

class FaultApiTests(unittest.TestCase):
    def test_server_error_and_delayed_response(self):
        server = create_server(0, read_delay=.15, read_error=True)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        url = f'http://127.0.0.1:{server.server_port}/vehicles'
        try:
            with self.assertRaises(TimeoutError):
                urlopen(url, timeout=.02)
            with self.assertRaises(HTTPError) as error:
                urlopen(url)
            self.assertEqual(error.exception.code, 503)
            error.exception.close()
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
