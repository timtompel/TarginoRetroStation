"""Optional HTTPS transport for hosts whose Windows TLS credentials are unavailable."""
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

for line in sys.stdin:
    try:
        item = json.loads(line)
        req = urllib.request.Request(item['url'], headers={'User-Agent': 'HydraCentral/1.0'})
        with urllib.request.urlopen(req, timeout=25) as response:
            data = response.read(8 * 1024 * 1024 + 1)
        if len(data) > 8 * 1024 * 1024:
            raise ValueError('Image/index exceeds 8 MB')
        Path(item['path']).write_bytes(data)
        result = {'ok': True}
    except urllib.error.HTTPError as error:
        result = {'ok': False, 'status': error.code, 'error': str(error)}
    except Exception as error:
        result = {'ok': False, 'status': 0, 'error': str(error)}
    print(json.dumps(result), flush=True)
