"""OpenRouter for lastshell's engines (dictate.py, reader.py): one key lookup,
one request path, one error shape. Standard library only.

The key: OPENROUTER_API_KEY in the environment, else
~/.config/lastshell/openrouter.key (mode 600; both machines have it), else the
OPENROUTER_API_KEY= line of ~/.config/openrouter.env (the desk's original).
"""
import json
import os
import urllib.error
import urllib.request
from pathlib import Path

API = 'https://openrouter.ai/api/v1'
_CONFIG = Path(os.environ.get('XDG_CONFIG_HOME') or Path.home() / '.config')
KEY_FILE = _CONFIG / 'lastshell' / 'openrouter.key'
ENV_FILE = _CONFIG / 'openrouter.env'


class OpenRouterError(Exception):
    """A request failed; str() is fit to show the user."""


def key():
    env = os.environ.get('OPENROUTER_API_KEY', '').strip()
    if env:
        return env
    try:
        k = KEY_FILE.read_text().strip()
        if k:
            return k
    except OSError:
        pass
    try:
        for line in ENV_FILE.read_text().splitlines():
            if line.startswith('OPENROUTER_API_KEY='):
                return line.split('=', 1)[1].strip().strip('"\'')
    except OSError:
        pass
    return ''


def _request(path, body, title):
    k = key()
    if not k:
        raise OpenRouterError(f'No OpenRouter key. Put it in {KEY_FILE} (chmod 600).')
    return urllib.request.Request(API + path, data=json.dumps(body).encode(), method='POST', headers={
        'Authorization': 'Bearer ' + k,
        'Content-Type': 'application/json',
        # attribution on the OpenRouter dashboard: spend per application
        'HTTP-Referer': 'https://github.com/slastra',
        'X-Title': title,
    })


def _http_error(e):
    detail = e.read().decode(errors='replace')[:300]
    try:
        detail = json.loads(detail)['error']['message']
    except (ValueError, KeyError, TypeError):
        pass
    return OpenRouterError(f'OpenRouter {e.code}: {detail}')


def post(path, body, *, timeout, title):
    """POST JSON to API + path and return the parsed reply."""
    req = _request(path, body, title)
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return json.load(r)
    except urllib.error.HTTPError as e:
        raise _http_error(e) from None
    except (urllib.error.URLError, TimeoutError, OSError) as e:
        raise OpenRouterError(f'Network error: {getattr(e, "reason", e)}') from None


def stream_chat(body, *, timeout, title, stop_event=None):
    """Stream one chat completion: yields ('text', piece) for each content
    delta, then ('finish', reason) so a caller can tell a complete answer from
    a truncated one. Reasoning deltas are never yielded. Returns early once
    stop_event is set."""
    req = _request('/chat/completions', {**body, 'stream': True}, title)
    try:
        resp = urllib.request.urlopen(req, timeout=timeout)
    except urllib.error.HTTPError as e:
        raise _http_error(e) from None
    with resp:
        finish = None
        for raw in resp:
            if stop_event is not None and stop_event.is_set():
                return
            line = raw.decode('utf-8', 'replace').strip()
            if not line.startswith('data:'):
                continue
            payload = line[5:].strip()
            if payload == '[DONE]':
                break
            try:
                chunk = json.loads(payload)
            except ValueError:
                continue
            for choice in chunk.get('choices') or []:
                piece = (choice.get('delta') or {}).get('content')
                if piece:
                    yield ('text', piece)
                if choice.get('finish_reason'):
                    finish = choice['finish_reason']
        yield ('finish', finish)
