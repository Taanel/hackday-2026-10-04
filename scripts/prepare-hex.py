"""Install the official pinned Hex app and explicitly prepare German Whisper."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import select
import shutil
import subprocess
import tempfile
from urllib.request import Request, urlopen

RELEASE = 'app-v2.1.24'
DMG_SHA = 'c017f381c5d966647f3d17cc90bff958415ddb4eb859491261c22ab5caa6d70d'

def prepare(support: Path) -> None:
    binary = support/'tools/Hex.app/Contents/MacOS/hex'
    if not binary.exists():
        with tempfile.TemporaryDirectory(prefix='friday-hex-') as temp:
            temp = Path(temp)
            dmg = temp/'hex.dmg'
            print('Offizielles Hex ARM64-Release wird geladen …',flush=True)
            with urlopen(f'https://github.com/anomalyco/hex/releases/download/{RELEASE}/HEX-2.1.24-arm64.dmg') as response, dmg.open('wb') as output:
                shutil.copyfileobj(response, output)
            if hashlib.sha256(dmg.read_bytes()).hexdigest() != DMG_SHA:
                raise RuntimeError('Hex download checksum mismatch')
            mount = temp/'volume'
            subprocess.run(['hdiutil','attach',str(dmg),'-readonly','-nobrowse','-mountpoint',str(mount)],check=True,stdout=subprocess.DEVNULL)
            try:
                binary.parent.parent.parent.parent.mkdir(parents=True,exist_ok=True)
                shutil.copytree(mount/'Hex.app',support/'tools/Hex.app',symlinks=True)
            finally:
                subprocess.run(['hdiutil','detach',str(mount)],check=True,stdout=subprocess.DEVNULL)
    env = dict(os.environ, HEX_APPLICATION_SUPPORT_DIR=str(support/'hex'))
    env.pop('TRANSCRIBE_DUMP_DIR',None)
    log_directory = support/'Logs'; log_directory.mkdir(parents=True,exist_ok=True)
    with (log_directory/'hex-setup.log').open('wb') as log:
        process = subprocess.Popen([str(binary),'service','--embedded'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=log,env=env)
        try:
            if not select.select([process.stdout],[],[],30)[0]: raise RuntimeError('Hex startup timeout')
            ready=json.loads(process.stdout.readline())
            if ready.get('apiVersion') != '2': raise RuntimeError('Hex API version unsupported')
            request=Request(ready['url']+'/models/whisper_large_v3_turbo/prepare?language=de',data=b'',
                            headers={'Authorization':'Bearer '+ready['token']},method='POST')
            succeeded=False
            with urlopen(request,timeout=600) as response:
                for line in response:
                    if not line.startswith(b'data:'): continue
                    event=json.loads(line[5:])
                    kind=event.get('type')
                    if kind=='error': raise RuntimeError('Hex model preparation failed; see hex-setup.log')
                    if kind=='downloading':
                        if event.get('downloadedBytes',0)==0:print('Deutsches Whisper-Modell wird geladen …',flush=True)
                    else: print('Hex: '+str(kind),flush=True)
                    if kind=='ok': succeeded=True
            if not succeeded:raise RuntimeError('Hex preparation ended without success')
        finally:
            process.stdin.close()
            try: process.wait(timeout=8)
            except subprocess.TimeoutExpired: process.kill(); process.wait()
    (support/'hex-release.json').write_text(json.dumps({'release':RELEASE,'dmgSHA256':DMG_SHA,'license':'MIT','model':'whisper_large_v3_turbo'},indent=2))

if __name__=='__main__':
    parser=argparse.ArgumentParser()
    parser.add_argument('--support',type=Path,required=True)
    prepare(parser.parse_args().support)
