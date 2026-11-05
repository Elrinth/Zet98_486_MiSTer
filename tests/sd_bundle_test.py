import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

s = importlib.util.spec_from_file_location('bundle', Path(__file__).resolve().parents[1]/'scripts/build_sd_bundle.py')
m = importlib.util.module_from_spec(s)
s.loader.exec_module(m)

class BundleTests(unittest.TestCase):
    def test_asset_hash_and_size_required(self):
        asset = {'name':'core.rbf','browser_download_url':'https://example.invalid/core','size':3,'digest':'sha256:'+m.sha(b'abc')}
        with patch.object(m,'fetch',return_value=b'abc'):
            self.assertEqual(m.asset_bytes(asset),b'abc')
            for field,value in [('size',4),('digest',None),('digest','sha256:'+m.sha(b'bad'))]:
                with self.assertRaises(ValueError): m.asset_bytes(dict(asset,**{field:value}))

    def test_ambiguous_component_is_rejected(self):
        with self.assertRaises(ValueError):
            m.one_asset({'assets':[{'name':'a.rbf'},{'name':'b.rbf'}]},lambda n:n.endswith('.rbf'))

    def test_lower_clock_build_stays_out(self):
        r={'assets':[{'name':'PC98_Z486_75_B279_20261105.rbf'},{'name':'PC98_Z486_90_B279_20261105.rbf'},{'name':'PC98_Bundle_B279.zip'}]}
        self.assertEqual(m.core_rbf(r)['name'],'PC98_Z486_90_B279_20261105.rbf')
        self.assertEqual(m.core_rbf({'assets':[{'name':'core.rbf'},{'name':'x.zip'}]})['name'],'core.rbf')
        for names in [['a.rbf','b.rbf'],['PC98_Z486_90_a.rbf','PC98_Z486_90_b.rbf'],['dir/PC98_Z486_90_a.rbf'],[]]:
            with self.assertRaises(ValueError): m.core_rbf({'assets':[{'name':n} for n in names]})

    def test_unpublished_or_unsafe_release_is_rejected(self):
        import json
        base={'draft':False,'prerelease':False,'tag_name':'B245'}
        for change in [{'draft':True},{'prerelease':True},{'tag_name':'../bad'}]:
            with patch.object(m,'fetch',return_value=json.dumps(dict(base,**change)).encode()):
                with self.assertRaises(ValueError): m.release(m.CORE,'latest')

if __name__ == '__main__': unittest.main()
