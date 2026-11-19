from unittest import TestCase
from unittest.mock import patch
from apps.diagnostics.result_store import clear_results, get_result, store_result


class VolatileResultStoreTests(TestCase):
    def setUp(self):
        clear_results()

    def tearDown(self):
        clear_results()

    def test_result_is_copied_and_duplicate_is_rejected(self):
        result = {"status": "healthy"}
        self.assertTrue(store_result("r1", result, ttl_seconds=60))
        result["status"] = "failed"
        self.assertEqual(get_result("r1"), {"status": "healthy"})
        self.assertFalse(store_result("r1", {"status": "failed"}, ttl_seconds=60))

    def test_result_expires(self):
        with patch("apps.diagnostics.result_store.time.monotonic", side_effect=[10, 71]):
            self.assertTrue(store_result("r1", {"status": "healthy"}, ttl_seconds=60))
            self.assertIsNone(get_result("r1"))
