import importlib.util
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

spec=importlib.util.spec_from_file_location('duckctl',Path(__file__).resolve().parents[1]/'cli/duckctl.py')
cli=importlib.util.module_from_spec(spec);spec.loader.exec_module(cli)


class CliTests(unittest.TestCase):
    def test_profiles_escape_strings_and_never_enable_before_confirmation(self):
        for mode in ('sta','ap'):
            text=cli.profile_text(mode,' 鸭子\\wifi ','password123','wlan0','123')
            self.assertIn('autoconnect=false',text)
            self.assertIn('ssid=\\s鸭子\\\\wifi\\s',text)
            self.assertIn('mode='+('ap' if mode=='ap' else 'infrastructure'),text)
            self.assertEqual('address1=10.42.0.1/24' in text,mode=='ap')

    def test_bad_ssid_password_and_interface_cannot_inject_profiles(self):
        for ssid,password,interface in [('x\n[wifi]','password1','wlan0'),('x','short','wlan0'),
                                        ('x'*33,'password1','wlan0'),('x','password1','wlan0\nfoo')]:
            with self.assertRaises(ValueError): cli.profile_text('ap',ssid,password,interface,'uuid')

    def test_relax_does_not_stop_services_or_power_off_board(self):
        with patch.object(cli,'root'),patch.object(cli,'rpc',return_value={'accepted':True}) as rpc,patch.object(cli,'run') as run:
            self.assertEqual(cli.main(['relax']),0)
            rpc.assert_called_once_with('robot.relax');run.assert_not_called()

    def test_sta_failure_restores_previous_and_deletes_only_new_profile(self):
        row={'token':'test','phase':'scheduled','created':True,'previous':'previous',
             'target':'new','interface':'wlan0'}
        with patch.object(cli,'nm') as nm,patch.object(cli,'save') as save:
            cli.rollback(row)
            self.assertIn(unittest.mock.call('connection','up','uuid','previous','ifname','wlan0'),nm.call_args_list)
            self.assertIn(unittest.mock.call('connection','delete','uuid','new'),nm.call_args_list)
            self.assertEqual(row['phase'],'rolled-back');save.assert_called_once()

    def test_committed_network_is_not_rolled_back_by_old_timer(self):
        with patch.object(cli,'nm') as nm,patch.object(cli,'save') as save:
            cli.rollback({'phase':'committed'})
            nm.assert_not_called();save.assert_not_called()

    def test_confirm_checks_actual_active_uuid(self):
        row={'token':'test','phase':'await-confirm','deadline':1e12,'target':'target','interface':'wlan0'}
        with tempfile.TemporaryDirectory() as folder,patch.object(cli,'RUN',Path(folder)),patch.object(cli,'PENDING',Path(folder)/'pending'),patch.object(cli,'root'),patch.object(cli,'load',return_value=row),patch.object(cli,'current_uuid',return_value='wrong'),patch.object(cli,'nm') as nm:
            with self.assertRaises(RuntimeError): cli.network_action('confirm','test')
            nm.assert_not_called()

    def test_profiles_reject_unknown_modes(self):
        with self.assertRaises(ValueError): cli.profile_text('bridge','ssid','password1','wlan0','uuid')
