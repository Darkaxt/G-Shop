"""Offline regression checks for the desktop packaging collector's API gate."""
import importlib.util
import json
from pathlib import Path
import unittest
from unittest.mock import MagicMock, patch


spec = importlib.util.spec_from_file_location(
    'packaging', Path(__file__).parents[1] / 'prepare_packaging_resources.py')
packaging = importlib.util.module_from_spec(spec)
spec.loader.exec_module(packaging)


class Response:
    status_code = 200
    headers = {}

    def __init__(self, body=b'fixture', status=200):
        self.body, self.status_code = body, status

    def __enter__(self):
        return self

    def __exit__(self, *args):
        return False

    def iter_content(self, size):
        yield self.body


class Session:
    def __init__(self):
        self.calls = 0
        self.media_status = 200
        self.account = {'id': 'fixture-user', 'maxthreads': '1',
            'maxrequestspermin': '30', 'maxrequestsperday': '5',
            'requeststoday': '1', 'maxrequestskoperday': '5', 'requestskotoday': '0'}

    def get(self, url, **kwargs):
        self.calls += 1
        if url.endswith('ssuserInfos.php'):
            assert kwargs['params']['output'] == 'json'
        return (Response(json.dumps({'response': {'ssuser': self.account}}).encode())
            if url.endswith('ssuserInfos.php') else Response(status=self.media_status))


class Clock:
    def __init__(self):
        self.now = 0
        self.waits = []

    def wait(self, delay):
        self.waits.append(delay)
        self.now += delay


class RequestBudgetTest(unittest.TestCase):
    url = 'https://api.screenscraper.fr/api2/mediaJeu.php'

    def budget(self, clock):
        return packaging.ScreenScraperBudget({'ssid': 'fixture-user'},
            clock=lambda: clock.now, wait=clock.wait)

    def test_uncached_screenscraper_request_cannot_bypass_budget(self):
        session = Session()
        with self.assertRaisesRegex(RuntimeError, 'rate-controlled'):
            packaging.fetch(session,
                'https://api.screenscraper.fr/api2/mediaJeu.php',
                params={'media': 'fanart'})
        self.assertEqual(session.calls, 0)

    def test_reported_rate_and_daily_budget_apply_before_dispatch(self):
        session, clock = Session(), Clock()
        budget = self.budget(clock)
        for _ in range(3):
            self.assertEqual(packaging.fetch(session, self.url,
                provider_budget=budget), b'fixture')
        self.assertEqual(clock.waits, [2, 2, 2])
        self.assertEqual(session.calls, 4)  # One account probe and three media.
        with self.assertRaisesRegex(RuntimeError, 'quota is exhausted'):
            packaging.fetch(session, self.url, provider_budget=budget)
        self.assertEqual(session.calls, 4)

    def test_unknown_or_zero_limits_are_not_unlimited(self):
        for field, value in [('maxrequestspermin', None), ('maxthreads', '0'),
                ('requeststoday', '5'), ('requestskotoday', '5')]:
            with self.subTest(field=field):
                session, clock = Session(), Clock()
                session.account[field] = value
                with self.assertRaises(RuntimeError):
                    packaging.fetch(session, self.url, provider_budget=self.budget(clock))
                self.assertEqual(session.calls, 1)  # No media request.

    def test_throttle_stops_without_retrying(self):
        session, clock = Session(), Clock()
        session.media_status = 429
        with self.assertRaisesRegex(RuntimeError, 'HTTP 429'):
            packaging.fetch(session, self.url, provider_budget=self.budget(clock))
        self.assertEqual(session.calls, 2)

    def test_cached_response_does_not_probe_or_consume_quota(self):
        cache = MagicMock()
        cache.__truediv__.return_value.exists.return_value = True
        cache.__truediv__.return_value.read_bytes.return_value = b'cached'
        session = Session()
        with patch.object(packaging, 'HTTP_CACHE', cache):
            self.assertEqual(packaging.fetch(session, self.url), b'cached')
        self.assertEqual(session.calls, 0)


if __name__ == '__main__':
    unittest.main()
