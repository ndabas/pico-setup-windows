#!/usr/bin/env python3
"""
Create zip files, with the added feature that file/directory names can differ from the source names.

The format is simply:
name # Add the file or directory (recursively)
dir/ # Add the contents of the directory, but not the directory itself
arcname: name # Add the file or directory, but use arcname as the name in the zip file

Loosely based on https://github.com/python/cpython/blob/5ec845a0444bc97d8a684dc99840daeb5fa8c1e9/Lib/zipfile/__init__.py#L2371
"""

import argparse
import io
import os
import sys
import tempfile
import unittest
from zipfile import ZipFile, ZIP_DEFLATED


def main(args=None):

    description = 'A simple command-line interface for zipfile module.'
    parser = argparse.ArgumentParser(description=description, fromfile_prefix_chars='@')
    parser.add_argument('-f', '--file', nargs='+',
                        metavar=('<name>', '<file>'),
                        help='Create zipfile from sources')
    parser.add_argument('-v', '--verbose', action='store_true',
                        help='Print verbose output')
    args = parser.parse_args(args)

    if args.file is not None:
        zip_name = args.file.pop(0)
        files = args.file

        def addToZip(zf, path, zippath):
            if os.path.isfile(path):
                if args.verbose:
                    print(f'Adding {path} as {zippath}')
                zf.write(path, zippath, ZIP_DEFLATED)
            elif os.path.isdir(path):
                if zippath:
                    if args.verbose:
                        print(f'Adding directory {path} as {zippath}')
                    zf.write(path, zippath)
                for nm in sorted(os.listdir(path)):
                    addToZip(zf,
                             os.path.join(path, nm), os.path.join(zippath, nm))
            # else: ignore

        with ZipFile(zip_name, 'w') as zf:
            for path in files:
                if ': ' in path:
                    zippath, path = path.split(': ', 1)
                else:
                    zippath = os.path.basename(path)
                if zippath in (os.curdir, os.pardir):
                    zippath = ''
                addToZip(zf, path, zippath)


# ---------------------------------------------------------------------------
# Tests — run with:  python -m unittest mkzip
# ---------------------------------------------------------------------------


class TestMkzip(unittest.TestCase):

    def setUp(self):
        tmp_dir = self.enterContext(tempfile.TemporaryDirectory())
        self.tmp = tmp_dir
        self.tree = os.path.join(tmp_dir, 'tree')
        self.lone = os.path.join(tmp_dir, 'lone.txt')
        self.out = os.path.join(tmp_dir, 'out.zip')
        os.makedirs(os.path.join(self.tree, 'sub'))
        for rel, content in [
            ('tree/a.txt', b'aaa'),
            ('tree/b.txt', b'bbb'),
            ('tree/sub/c.txt', b'ccc'),
            ('lone.txt', b'lone'),
        ]:
            with open(os.path.join(tmp_dir, rel), 'wb') as f:
                f.write(content)

    def _names(self, zip_path):
        with ZipFile(zip_path) as zf:
            return sorted(zf.namelist())

    def _read(self, zip_path, name):
        with ZipFile(zip_path) as zf:
            return zf.read(name)

    def test_single_file(self):
        main(['-f', self.out, self.lone])
        self.assertEqual(self._names(self.out), ['lone.txt'])
        self.assertEqual(self._read(self.out, 'lone.txt'), b'lone')

    def test_file_with_arcname(self):
        main(['-f', self.out, f'renamed.txt: {self.lone}'])
        self.assertEqual(self._names(self.out), ['renamed.txt'])
        self.assertEqual(self._read(self.out, 'renamed.txt'), b'lone')

    def test_directory_with_arcname(self):
        main(['-f', self.out, f'mydir: {self.tree}'])
        names = self._names(self.out)
        self.assertIn('mydir/a.txt', names)
        self.assertIn('mydir/b.txt', names)
        self.assertIn('mydir/sub/c.txt', names)
        self.assertEqual(self._read(self.out, 'mydir/a.txt'), b'aaa')
        self.assertEqual(self._read(self.out, 'mydir/sub/c.txt'), b'ccc')

    def test_directory_default_arcname(self):
        """Without an arcname the directory's basename is used as the root."""
        main(['-f', self.out, self.tree])
        names = self._names(self.out)
        self.assertIn('tree/a.txt', names)
        self.assertIn('tree/sub/c.txt', names)

    def test_directory_no_trailing_sep_includes_dir(self):
        """A path without a trailing separator includes the directory itself as a prefix."""
        main(['-f', self.out, self.tree])  # no trailing sep
        names = self._names(self.out)
        self.assertTrue(all(n.startswith('tree/') or n == 'tree' for n in names))
        self.assertNotIn('a.txt', names)
        self.assertNotIn('sub/c.txt', names)

    def test_directory_trailing_sep_omits_dir(self):
        """A path with a trailing separator adds only the directory's contents, not the directory itself."""
        main(['-f', self.out, self.tree + os.sep])  # trailing sep
        names = self._names(self.out)
        self.assertIn('a.txt', names)
        self.assertIn('b.txt', names)
        self.assertIn('sub/c.txt', names)
        self.assertNotIn('tree/a.txt', names)
        self.assertNotIn('tree', names)

    def test_multiple_inputs(self):
        inputs_file = os.path.join(self.tmp, 'inputs.txt')
        with open(inputs_file, 'w') as f:
            f.write(f'{self.lone}\n')
            f.write(f'mydir: {self.tree}\n')
        main(['-f', self.out, f'@{inputs_file}'])
        names = self._names(self.out)
        self.assertIn('lone.txt', names)
        self.assertIn('mydir/a.txt', names)
        self.assertIn('mydir/sub/c.txt', names)

    def test_arcname_split_on_first_colon(self):
        """A colon in the source path must not confuse the arcname split."""
        # source path on Windows contains a drive colon but no space after it
        main(['-f', self.out, f'deep/file.txt: {self.lone}'])
        self.assertIn('deep/file.txt', self._names(self.out))

    def test_no_file_argument_is_noop(self):
        """Calling without -f should not raise."""
        main([])

    def test_verbose_output(self):
        buf = io.StringIO()
        old_stdout, sys.stdout = sys.stdout, buf
        try:
            main(['-f', self.out, self.lone, '-v'])
        finally:
            sys.stdout = old_stdout
        self.assertIn('lone.txt', buf.getvalue())


if __name__ == '__main__':
    main()
