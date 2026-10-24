import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('lew_management', ROOT/'console/management_profile.py')
management = importlib.util.module_from_spec(spec)
spec.loader.exec_module(management)

class CompatibilityTests(unittest.TestCase):
    def test_v01_service_is_supported(self):
        self.assertTrue(management.supports_feature({'build':'1fa8438-feetech-control.43-ft01.1'}, 'supported'))

    def test_ft6_service_remains_supported(self):
        self.assertTrue(management.supports_feature({'build':'1fa8438-feetech-ft6-control.43'}, 'supported'))

    def test_explicit_refusal_takes_priority(self):
        self.assertFalse(management.supports_feature({'build':'1fa8438-feetech-control.43-ft01.1','management_capabilities':{'supported':False}}, 'supported'))

    def test_unknown_service_is_not_implicitly_supported(self):
        self.assertFalse(management.supports_feature({'build':'unknown'}, 'supported'))

    def test_unknown_feature_is_not_granted(self):
        self.assertFalse(management.supports_feature({'build':'1fa8438-feetech-control.43-ft01.1'}, 'unknown_feature'))

    def test_old_service_does_not_gain_motion(self):
        self.assertFalse(management.supports_feature({'build':'590b986-feetech-ft6-control.7'}, 'motion'))

if __name__ == '__main__':
    unittest.main()
