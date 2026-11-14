"""Offline regression tests for the official announcement extractor."""
import unittest

from update_loot_filter_data import Post


class PostTests(unittest.TestCase):
    def test_reads_only_the_news_post_content(self):
        html = '''<div class="content"><div>Site navigation</div>
        <table><tr class="newsPost"><td><div class="content">
        <h3>Removed Items</h3><div class="spoiler"><ul><li>Orb of Binding</li></ul></div>
        </div></td></tr><tr><td><div class="content">A reply</div></td></tr></table>
        <div>Report Forum Post 12345Next</div></div>'''
        post = Post()
        post.feed(html)
        text = "".join(post.parts)
        self.assertIn("Removed Items", text)
        self.assertIn("Orb of Binding", text)
        self.assertNotIn("Site navigation", text)
        self.assertNotIn("A reply", text)
        self.assertNotIn("Report Forum Post", text)


if __name__ == "__main__":
    unittest.main()
