#!/usr/bin/env python3
"""Read-only capture of the existing VM. Run from Mac Terminal."""
import datetime
import getpass
import pathlib
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
host = sys.argv[1] if len(sys.argv) > 1 else 'admiral@10.42.65.171'
if host.startswith('-'):
    sys.exit('Invalid SSH destination')
dest = ROOT / 'private' / datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
dest.mkdir(parents=True, mode=0o700)
# sudo reads the password from stdin. Never store it in argv, files, or shell history.
password = getpass.getpass('VM sudo password: ') + '\n'
def remote(command, output):
    with (dest / output).open('wb') as f:
        result = subprocess.run(['ssh', '-o', 'ConnectTimeout=15', host, command],
                                input=password.encode(), stdout=f)
    if result.returncode:
        sys.exit(f'Capture failed: {output}. Partial files are private in {dest}')
remote("sudo -S -p '' sh -c 'cd /root/elastic-ad && find . -maxdepth 4 -type f ! -path \"*/data/*\" ! -path \"*/.git/*\" ! -path \"*/node_modules/*\" -print'", 'file-list.txt')
# Capture deployment source, not live database files. Review unknown large paths first.
print(f'File inventory saved to {dest}/file-list.txt')
print('The next step copies config/source excluding common database and log directories.')
remote("sudo -S -p '' tar --exclude='./data' --exclude='./esdata' --exclude='./elasticsearch-data' --exclude='./kibanadata' --exclude='./logs' --exclude='./.git' --exclude='./node_modules' --exclude='*.log' -czf - -C /root/elastic-ad .", 'source.tar.gz')
remote("sudo -S -p '' sh -c 'docker version; docker compose version; docker ps -a --format \"table {{.Names}}\\t{{.Image}}\\t{{.Ports}}\\t{{.Status}}\"; docker volume ls; docker ps -aq | xargs -r docker inspect --format \"{{.Name}} {{json .Mounts}} {{json .Config.Labels}}\"'", 'inventory.txt')
print(f'Captured to {dest}. Contains secrets: do not commit. No services were changed.')
