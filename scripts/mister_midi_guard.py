#!/usr/bin/env python3
"""Silence the local synth when leaving/reloading Zet98; never reads the UART."""
import argparse, socket, time
from pathlib import Path

def snapshot(path):
    try:
        s=path.stat()
        return (path.read_text().strip(),s.st_mtime_ns,s.st_ino)
    except OSError:
        return None

def panic(port=9800):
    with socket.create_connection(('127.0.0.1',port),1) as sock:
        sock.settimeout(.2)
        data=''.join('cc %d %d 0\n'%(ch,cc) for ch in range(16) for cc in (64,120,123,121))
        sock.sendall(data.encode('ascii'))

def changed(old,new):
    return old is not None and old[0].lower().startswith('zet98') and old!=new

def main():
    import fcntl
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--once',action='store_true')
    args=p.parse_args()
    if args.once:
        panic();return
    with open('/tmp/zet98-midi-guard.lock','w') as lock:
        try:fcntl.flock(lock,fcntl.LOCK_EX|fcntl.LOCK_NB)
        except BlockingIOError:return
        path=Path('/tmp/CORENAME');old=snapshot(path)
        while True:
            time.sleep(.1);new=snapshot(path)
            if changed(old,new):
                try:panic();print('Silenced synth after Zet98 transition',flush=True)
                except OSError:pass # No local synth running: nothing to silence.
            old=new
if __name__=='__main__':main()
