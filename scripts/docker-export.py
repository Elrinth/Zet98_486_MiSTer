#!/usr/bin/env python3
"""Export a generated Docker directory without applying Linux timestamps.

Docker Desktop's direct `cp` can fail with Windows `chtimes: parameter is
incorrect` on generated Quartus database directories. Stream the tar archive
as bytes, validate its paths/types, and unpack with attributes disabled.
"""
import argparse
import os
from pathlib import Path, PurePosixPath
import subprocess
import tarfile
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--context', default='desktop-linux')
    parser.add_argument('--archive', type=Path, help='Tar already exported by the bounded PowerShell runner')
    parser.add_argument('container')
    parser.add_argument('source')
    parser.add_argument('destination', type=Path)
    args = parser.parse_args()
    destination = args.destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    archive = args.archive
    if archive is None:
        fd, archive_name = tempfile.mkstemp(prefix='quartus-export-', suffix='.tar', dir=str(destination.parent))
        archive = Path(archive_name)
        with os.fdopen(fd, 'wb') as stream:
            # Legacy callers are bounded too. New Windows build/report callers
            # use docker-command.ps1, including child-tree cleanup on timeout.
            try:
                result = subprocess.run(['docker', '--context', args.context, 'cp',
                                         args.container + ':' + args.source.rstrip('/') + '/.', '-'],
                                        stdout=stream, stderr=subprocess.PIPE, timeout=60)
            except subprocess.TimeoutExpired:
                raise SystemExit('Docker export timed out; partial archive retained at {}'.format(archive))
        if result.returncode:
            raise SystemExit('Docker export failed; archive retained at {}\n{}'.format(
                archive, result.stderr.decode('utf-8', 'replace')))
    with tarfile.open(str(archive), 'r:') as tar:
        members = tar.getmembers()
        for member in members:
            name = PurePosixPath(member.name)
            if (name.is_absolute() or '..' in name.parts or '\\' in member.name or
                    ':' in member.name or not (member.isfile() or member.isdir())):
                raise SystemExit('Unsafe archive member {}; archive retained at {}'.format(member.name, archive))
            target = destination.joinpath(*name.parts).resolve()
            if os.path.commonpath([str(destination), str(target)]) != str(destination):
                raise SystemExit('Archive target escapes destination; archive retained at {}'.format(archive))
        for member in members:
            tar.extract(member, str(destination), set_attrs=False)
    archive.unlink()
    print('Exported {} files/directories to {}'.format(len(members), destination))


if __name__ == '__main__':
    main()
