"""Build hash-verified, versioned SD-card bundles from public GitHub releases."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
import zipfile

CORE = 'Elrinth/Zet98_486_MiSTer'
BIOS = 'Elrinth/PC98_Open_BIOS'
ROOT = Path(__file__).resolve().parents[1]
HELPERS = ['mister_midi_install.py', 'mister_midi_irq_guard.py',
           'mister_midi_setup.sh', 'mister_fluidsynth_wrapper.sh',
           'mister_midi_timing_README.txt', 'mister_midi_menu.sh']
LICENSES = ['rtl/vendor/ao486-LICENSE', 'rtl/vendor/z486/LICENSE',
            'rtl/vendor/z486/LICENSE-SCOPE.md', 'rtl/vendor/jt08/jt49/LICENSE',
            'rtl/vendor/jt08/jt12/LICENSE']

def sha(data):
    return hashlib.sha256(data).hexdigest()

def fetch(url):
    headers = {'User-Agent': 'PC98-SD-bundle'}
    if url.startswith('https://api.github.com/') and os.environ.get('GH_TOKEN'):
        headers['Authorization'] = 'Bearer ' + os.environ['GH_TOKEN']
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=90) as r:
        return r.read()

def release(repo, tag):
    suffix = 'latest' if tag == 'latest' else 'tags/' + urllib.parse.quote(tag, safe='')
    r = json.loads(fetch('https://api.github.com/repos/' + repo + '/releases/' + suffix))
    if r['draft'] or r['prerelease']:
        raise ValueError('Bundles require published, non-prerelease components')
    if not re.fullmatch(r'[A-Za-z0-9._-]+', r['tag_name']):
        raise ValueError('Unsupported release tag')
    return r

def asset_bytes(asset):
    data = fetch(asset['browser_download_url'])
    if len(data) != asset['size'] or asset.get('digest') != 'sha256:' + sha(data):
        raise ValueError('Missing or mismatched published asset digest: ' + asset['name'])
    return data

def one_asset(r, predicate):
    found = [a for a in r['assets'] if predicate(a['name'])]
    if len(found) != 1:
        raise ValueError('Expected one component asset, found %d' % len(found))
    return found[0]

def main():
    p = argparse.ArgumentParser()
    p.add_argument('--core', default='latest')
    p.add_argument('--bios', default='latest')
    p.add_argument('--output', default='build/sd-bundle')
    args = p.parse_args()
    core, bios = release(CORE, args.core), release(BIOS, args.bios)
    rbf = one_asset(core, lambda n: n.endswith('.rbf') and '/' not in n and '\\' not in n)
    bz = one_asset(bios, lambda n: n.startswith('PC98_Open_BIOS_') and n.endswith('.zip'))
    helpers = {n: (ROOT/'scripts'/n).read_bytes().replace(b'\r\n', b'\n') for n in HELPERS}
    midi = sha(b''.join(n.encode()+b'\0'+helpers[n]+b'\0' for n in sorted(helpers)))[:12]
    name = 'PC98_Bundle_%s_BIOS-%s_MIDI-%s' % (core['tag_name'], bios['tag_name'], midi)
    out = Path(args.output).resolve()
    out.mkdir(parents=True, exist_ok=True)
    seven = shutil.which('7z') or shutil.which('7zz')
    if not seven and Path('C:/Program Files/7-Zip/7z.exe').exists():
        seven = 'C:/Program Files/7-Zip/7z.exe'
    if not seven:
        raise RuntimeError('7-Zip is required')
    with tempfile.TemporaryDirectory(prefix='pc98-bundle-') as temp:
        stage = Path(temp)
        def put(path, data):
            dest = stage/path
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(data.encode('utf-8') if isinstance(data, str) else data)
        put('_Computer/'+rbf['name'], asset_bytes(rbf))
        with zipfile.ZipFile(io.BytesIO(asset_bytes(bz))) as z:
            rom = z.read('boot.rom')
            if len(rom) != 550912:
                raise ValueError('Unexpected OpenBIOS layout; review bundle compatibility')
            put('games/PC98/boot.rom', rom)
            for n in ['LICENSE', 'LICENSES/NP2kai.txt', 'LICENSES/Shinonome.txt']:
                put('PC98-LICENSES/OpenBIOS/'+n, z.read(n))
        for n, data in helpers.items():
            put('Scripts/PC98_MIDI_Setup.sh' if n == 'mister_midi_menu.sh' else 'Scripts/pc98-midi-timing/'+n, data)
        for n in LICENSES:
            put('PC98-LICENSES/core/'+n, fetch('https://raw.githubusercontent.com/'+CORE+'/'+core['tag_name']+'/'+n))
        put('PC98-CORE-RELEASE-NOTES.txt', core.get('body') or '')
        put('PC98-BIOS-RELEASE-NOTES.txt', bios.get('body') or '')
        put('PC98-LICENSES/SOURCES.txt',
            'Core source and embedded notices: https://github.com/'+CORE+'/tree/'+core['tag_name']+'\n'
            'Core source archive: https://github.com/'+CORE+'/archive/refs/tags/'+core['tag_name']+'.zip\n'
            'OpenBIOS source: https://github.com/'+BIOS+'/tree/'+bios['tag_name']+'\n'
            'MIDI helper source is included in Scripts/pc98-midi-timing/.\n')
        put('PC98-README.txt', '''PC98 SD-card bundle: {core} / OpenBIOS {bios}

Back up games/PC98/boot.rom first: extraction replaces that file.
Extract the archive CONTENTS to the SD-card root (/media/fat), merging folders.
Requires an existing MiSTer installation and SDRAM module.
Load {rbf} from the Computer menu and mount your own disks.
Reload the core completely after changing the BIOS; OSD Reset is insufficient.

MIDI tuning is OPTIONAL and is not activated by extracting this archive.
Existing tuning remains unchanged. Run Scripts > PC98_MIDI_Setup to enable,
update or undo it, then reboot. Requires existing MidiLink/FluidSynth, Python3,
taskset and mountpoint. About 85 ms buffering, roughly 64 ms more than the old
configuration; this can reduce clumping but adds latency. Tempo is unchanged.
The helper preserves soundfont selection and unrelated startup commands.

Automatically packaged from published releases; packaging is not hardware
qualification. Read PC98-CORE-RELEASE-NOTES.txt and PC98-BIOS-RELEASE-NOTES.txt
for validation and limitations, including any pending on-device tests.
No games, DOS, soundfonts, NEC ROMs or personal configuration are included.
https://pc98.thefirstboss.com/downloads/
'''.format(core=core['tag_name'], bios=bios['tag_name'], rbf=Path(rbf['name']).stem))
        payloads = {f.relative_to(stage).as_posix(): sha(f.read_bytes()) for f in sorted(stage.rglob('*')) if f.is_file()}
        put('SHA256SUMS.txt', ''.join(h+'  '+n+'\n' for n,h in payloads.items()))
        # Fixed metadata makes retries reproducible; archived payload hashes
        # are verified before any release asset is uploaded.
        for f in stage.rglob('*'):
            if f.is_file(): os.utime(f, (946684800, 946684800))
        zp = out/(name+'.zip')
        with zipfile.ZipFile(zp, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
            for f in sorted(stage.rglob('*')):
                if f.is_file(): z.write(f, f.relative_to(stage).as_posix())
        with zipfile.ZipFile(zp) as z:
            if z.testzip(): raise ValueError('ZIP integrity failure')
            for n,h in payloads.items():
                if sha(z.read(n)) != h: raise ValueError('ZIP payload mismatch')
        sp = out/(name+'.7z')
        if sp.exists(): sp.unlink()
        subprocess.run([seven,'a','-t7z','-mx=9','-mtc=off','-mta=off',str(sp),'.'],cwd=stage,check=True,stdout=subprocess.DEVNULL)
        subprocess.run([seven,'t',str(sp)],check=True,stdout=subprocess.DEVNULL)
        manifest = {'bundle':name,'core':core['tag_name'],'bios':bios['tag_name'],'midi':midi,
                    'rbf':rbf['name'],'coreRelease':core['html_url'],'biosRelease':bios['html_url'],
                    'hardwareQualification':'See included component release notes; bundling adds no hardware qualification.',
                    'payloads':payloads,'archives':{f.name:{'bytes':f.stat().st_size,'sha256':sha(f.read_bytes())} for f in [zp,sp]}}
        (out/(name+'.json')).write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')
        print(json.dumps({k:manifest[k] for k in ['bundle','core','bios','midi','archives']},indent=2))

if __name__ == '__main__':
    main()
