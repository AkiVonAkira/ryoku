#!/usr/bin/env python3

import unittest

import sync


class CopyDetectionTest(unittest.TestCase):
    def test_leading_placeholder_sentence_is_copy(self):
        self.assertTrue(sync._copy("%d orphaned package(s)"))
        self.assertTrue(sync._copy("%s is unavailable: %s"))

    def test_bare_placeholder_is_not_copy(self):
        self.assertFalse(sync._copy("%s"))
        self.assertFalse(sync._copy("%02d"))


if __name__ == "__main__":
    unittest.main()
