#!/usr/bin/env python3
"""Sprawdź wybór SDK sondy; nie udawaj kompilacji macOS na Linuksie."""
import contextlib
import io
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name('test_content_time_list.py')
SDK = '/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk'
COMPILER = '/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc'


class CompilationIntercepted(Exception):
    """Zatrzymaj test na granicy uruchomienia prawdziwego kompilatora."""


class ToolchainTests(unittest.TestCase):
    def invoke(self, platform, *, write=True, sdk_error=False):
        calls = []
        queries = []

        def query(command, **kwargs):
            queries.append(command)
            if sdk_error:
                raise subprocess.CalledProcessError(1, command, stderr='SDK niedostępne')
            return SDK + '\n'

        def compile_command(command, **kwargs):
            calls.append(command)
            raise CompilationIntercepted()

        with tempfile.TemporaryDirectory(prefix='content-time-toolchain-') as output:
            argv = [str(SCRIPT), '--out', output] + (['--zapisz'] if write else [])
            with patch.object(sys, 'argv', argv), patch.object(sys, 'platform', platform), \
                 patch.dict(os.environ, {'SWIFTC': COMPILER, 'SDKROOT': '/inny/iPhoneOS.sdk'}), \
                 patch('subprocess.check_output', side_effect=query), \
                 patch('subprocess.run', side_effect=compile_command), \
                 contextlib.redirect_stdout(io.StringIO()) as stdout:
                try:
                    runpy.run_path(str(SCRIPT), run_name='__main__')
                except CompilationIntercepted:
                    pass
                except SystemExit as error:
                    self.assertEqual(error.code, 0)
        return calls, queries, stdout.getvalue()

    def test_macos_passes_explicit_host_sdk_even_with_iphone_sdkroot(self):
        calls, queries, _ = self.invoke('darwin')
        self.assertEqual(len(calls), 1)
        command = calls[0]
        self.assertIn('-sdk', command, 'Sonda macOS musi jawnie wskazać SDK hosta')
        self.assertEqual(command[command.index('-sdk') + 1], SDK)
        self.assertEqual(queries, [['xcrun', '--sdk', 'macosx', '--show-sdk-path']])
        self.assertEqual(command[0], COMPILER)

    def test_linux_does_not_ask_xcrun_or_pass_apple_sdk(self):
        calls, queries, _ = self.invoke('linux')
        self.assertEqual(len(calls), 1)
        self.assertNotIn('-sdk', calls[0])
        self.assertEqual(queries, [])

    def test_plan_does_not_query_sdk_or_compile(self):
        calls, queries, stdout = self.invoke('darwin', write=False)
        self.assertEqual(calls, [])
        self.assertEqual(queries, [])
        self.assertIn('"mode": "plan"', stdout)


if __name__ == '__main__':
    unittest.main(verbosity=2)
