import http.client
import threading
import unittest
from http.server import ThreadingHTTPServer

from check_result import check
from serve import Handler


class ResultTests(unittest.TestCase):
    def test_only_a_complete_six_test_pass_is_accepted(self):
        good = dict(result="Passed", totalTestCount=6, passedTests=6, failedTests=0, skippedTests=0)
        check(good)
        for changes in [dict(totalTestCount=0, passedTests=0), dict(totalTestCount=5, passedTests=5),
                        dict(totalTestCount=7, passedTests=7), dict(passedTests=5),
                        dict(skippedTests=1), dict(failedTests=1), dict(result="Failed")]:
            with self.subTest(changes=changes), self.assertRaises(ValueError):
                check(good | changes)
        with self.assertRaises(ValueError):
            check({})


class FeedTests(unittest.TestCase):
    def test_local_feed_links_to_local_page_and_unknown_paths_fail(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        try:
            base = f"http://127.0.0.1:{server.server_port}"
            connection = http.client.HTTPConnection("127.0.0.1", server.server_port)
            connection.request("GET", "/feed.xml")
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertEqual(response.getheader("Content-Type"), "application/rss+xml; charset=utf-8")
            text = response.read().decode()
            self.assertIn(f"<link>{base}/article</link>", text)
            self.assertIn("Smoke local feed", text)
            connection.request("GET", "/article")
            response = connection.getresponse()
            self.assertEqual(response.status, 200)
            self.assertIn(b"Smoke original page", response.read())
            connection.request("GET", "/missing")
            response = connection.getresponse()
            self.assertEqual(response.status, 404)
            response.read()
            connection.close()
        finally:
            server.shutdown()
            thread.join()
            server.server_close()


if __name__ == "__main__":
    unittest.main()
