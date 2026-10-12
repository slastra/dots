#!/usr/bin/env python3
"""
reader.py - lastshell's narrator engine (Super+T). It was piper-reader, a GTK
app; the speech pipeline below is unchanged, and the window became the
headless Reader at the bottom, which lastshell's Reader service drives over
stdin/stdout (see the protocol there).

Speak selected or copied text aloud with Piper.

Synthesis is streamed, not batched. Text is normalized, split into sentence
groups, and each group is rendered to a small WAV by piper-tts and appended to
an mpv playlist that is already playing. Audio therefore starts after the first
passage rather than after the whole document, which is what makes a 5000-word
article (~28 minutes of speech) usable.

Terminal output is rewritten for speech first by a model on OpenRouter. That
stage streams too, so its sentences feed Piper as they arrive rather than
holding up playback.

mpv is driven over its JSON IPC socket, which supplies pause, per-passage
skipping and pitch-corrected speed control without any audio code here.

Note: the TTS binary is `piper-tts`. `/usr/bin/piper` is the libratbag mouse
configuration GUI and has nothing to do with speech.
"""

import gi
from gi.repository import GLib

try:
    gi.require_version('GLibUnix', '2.0')
    from gi.repository import GLibUnix
    unix_signal_add = GLibUnix.signal_add
except (ValueError, ImportError):
    unix_signal_add = GLib.unix_signal_add

import atexit
import ctypes
import fcntl
import json
import os
import re
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
import unicodedata
import wave
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import openrouter  # noqa: E402  (scripts/openrouter.py, shared with dictate.py)

APP_ID = 'us.lastra.PiperReader'
PIPER = '/usr/bin/piper-tts'
# The user directory is searched too, so a voice fetched by hand shows up in
# the dropdown alongside the packaged ones. First match by name wins, which
# lets a local copy shadow a packaged voice of the same name.
VOICE_ROOTS = [
    Path('/usr/share/piper-voices'),
    Path.home() / '.local' / 'share' / 'piper-voices',
]
# Kokoro (2025) against piper (2023): comparable on CPU, ~5x faster on CUDA,
# 24 kHz, and 54 voices in one file. piper is kept because it carries the
# character voices kokoro has no equivalent for.
# British male, chosen to stay unmistakable against claude-speak's ff_siwis
# (French female): different on accent and register both, so a spoken cue can
# never be mistaken for the document being read.
DEFAULT_VOICE = 'kokoro-bm_george'

KOKORO_DIR = Path.home() / '.local' / 'share' / 'kokoro'
KOKORO_MODEL = KOKORO_DIR / 'kokoro-v1.0.onnx'
KOKORO_VOICES_BIN = KOKORO_DIR / 'voices-v1.0.bin'
KOKORO_LANG = 'en-us'
KOKORO_SPEAKERS = {
    'af': 'American female', 'am': 'American male',
    'bf': 'British female', 'bm': 'British male',
    'ef': 'Spanish female', 'em': 'Spanish male',
    'ff': 'French female',
    'hf': 'Hindi female', 'hm': 'Hindi male',
    'if': 'Italian female', 'im': 'Italian male',
    'jf': 'Japanese female', 'jm': 'Japanese male',
    'pf': 'Portuguese female', 'pm': 'Portuguese male',
    'zf': 'Chinese female', 'zm': 'Chinese male',
}

MAX_WORDS = 80         # above this a single sentence is split on clauses
CLAUSE_WORDS = 40      # target piece size when splitting an oversized sentence
MAX_CHARS = 400        # hard ceiling; text with no spaces evades the word limit
LOOKAHEAD = 60         # sentences rendered ahead of the playhead (~5 min, ~12 MB)

TIDY_BLOCK_WORDS = 700     # raw words per rewrite request
TIDY_AUTO_THRESHOLD = 0.35  # terminal-likeness above which Auto tidies
TIDY_AUTO_MAX_WORDS = 4000  # Auto skips very long documents; they are prose

# GLM Flash reaches its first content token in about half the time of Haiku
# (0.52 s vs 1.07 s measured) and costs a fraction as much, which matters here
# because the whole design is that audio starts within a second. Set
# PIPER_READER_TIDY_MODEL=anthropic/claude-haiku-4.5 for a more careful rewrite.
TIDY_MODEL = os.environ.get('PIPER_READER_TIDY_MODEL', 'z-ai/glm-5.3-flash')
TIDY_TIMEOUT = 45          # seconds for one block's stream

_CONFIG_HOME = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
CONFIG_PATH = _CONFIG_HOME / 'lastshell' / 'reader.json'
OLD_CONFIG_PATH = _CONFIG_HOME / 'piper-reader' / 'config.json'   # the GTK app's

TIDY_MODES = ['Off', 'Auto', 'Always']

TIDY_SYSTEM = """You rewrite text so a speech synthesizer can read it aloud naturally.

Rules:
- Never spell out punctuation. Do not say "dot", "slash", "dash", "underscore".
- Refer to a file by its bare name, never its path. Drop directories entirely.
- Turn command lines, logs, diffs and stack traces into plain narration of what
  happened. Summarize repetitive or tabular output instead of enumerating it.
- Read version numbers and short hashes only when they matter; otherwise omit.
- Stay faithful. Never invent detail that is not present.
- Output only the rewritten prose. No preamble, headings, or commentary."""


def _load_venv_packages():
    """The kokoro engine (kokoro_onnx, onnxruntime-gpu, phonemizer, espeak,
    soundfile) lives in a venv built with --system-site-packages so that gi
    still resolves. It is added to the import path here and imported lazily in
    KokoroEngine. A missing venv disables kokoro and leaves piper.

    This venv also used to carry anthropic and boto3 for the Bedrock rewrite
    stage, which is why removing "the Bedrock venv" broke model loading on
    2026-09-10: it was never only the Bedrock venv. Those packages are now dead
    weight in it, but the path hook is load-bearing for speech.
    """
    base = Path.home() / '.local' / 'share' / 'piper-reader' / 'venv'
    for lib in base.glob('lib/python*/site-packages'):
        if str(lib) not in sys.path:
            sys.path.append(str(lib))


_load_venv_packages()




# --------------------------------------------------------------------------
# Text normalization
#
# Arbitrary copied text is the hard part of this program, not the audio. Text
# from web pages and PDFs arrives hyphenated across line breaks, hard-wrapped
# mid-paragraph, full of markdown, and studded with bare URLs that Piper will
# otherwise read out one character at a time.
# --------------------------------------------------------------------------

ZERO_WIDTH = dict.fromkeys(
    map(ord, '​‌‍⁠﻿­'), None)

PUNCT_MAP = {
    '‘': "'", '’': "'", '‚': "'", '‛': "'",
    '“': '"', '”': '"', '„': '"',
    # A literal "..." gets collapsed back to "." by RE_MULTI_PUNCT, which
    # invents a sentence break: "Wait… what?" became two utterances.
    '…': ', ',
    ' ': ' ', ' ': ' ', ' ': ' ', ' ': ' ',
    '•': ' ', '·': ' ', '●': ' ', '▪': ' ',
    '→': ' to ', '←': ' from ',
}

# Applied BEFORE unicodedata.normalize, which folds these into bare letters or
# into a fraction slash espeak drops entirely — "½ cup" was read as "one two
# cup", and "m²" as "em two".
PRE_NFKC = {
    '№': ' number ', '½': ' one half', '⅓': ' one third', '⅔': ' two thirds',
    '¼': ' one quarter', '¾': ' three quarters', '⅛': ' one eighth',
    '²': ' squared', '³': ' cubed', '°': ' degrees',
    '™': ' ', '®': ' ', '©': ' ', '×': ' by ', '÷': ' divided by ',
}

# "3 * 4" is multiplication, not emphasis — say it rather than delete it.
RE_TIMES = re.compile(r'(?<=\d)[ \t]*\*[ \t]*(?=\d)')
# Whatever asterisks survive the paired-emphasis passes: unclosed "**bold",
# bullet leftovers, decorative "***". espeak otherwise reads them as "asterisk".
RE_STRAY_STAR = re.compile(r'\*+')

RE_ELLIPSIS = re.compile(r'\.{3,}')
# Year ranges only: a general digit-hyphen-digit rule would turn phone numbers
# and subtraction into "to".
RE_YEAR_RANGE = re.compile(r'\b(\d{4})[ \t]*-[ \t]*(\d{4})\b')

# espeak reads a bare "#" as "hash", so "#1" becomes "hash one". Only a "#"
# that introduces digits is a number sign; "#fff" and "C#" are left alone.
RE_NUMBER_SIGN = re.compile(r'#(?=\d)')

RE_CODE_FENCE = re.compile(r'^[ \t]*```.*?^[ \t]*```', re.M | re.S)
RE_CODE_FENCE_BODY = re.compile(r'^[ \t]*```[^\n]*\n(.*?)^[ \t]*```', re.M | re.S)
RE_HYPHEN_BREAK = re.compile(r'(\w)[-‐‑]\n[ \t]*(\w)')
RE_MD_IMAGE = re.compile(r'!\[([^\]]*)\]\([^)]*\)')
RE_MD_LINK = re.compile(r'\[([^\]]+)\]\([^)]*\)')
RE_URL = re.compile(r'<?\b(?:https?://|www\.)[^\s>]+>?')
# Punctuation that ends the sentence rather than the URL. Without putting it
# back, "See https://example.com. Then we left." lost its full stop and became
# a single run-on utterance.
URL_TRAIL = '.,;:!?)]}\'"'
RE_FOOTNOTE = re.compile(r'\[\d{1,3}\]')
# (?!\d) so "#1" is read as a number rather than treated as a heading marker
# and silently stripped down to "1".
RE_HEADING = re.compile(r'^[ \t]{0,3}#{1,6}(?!\d)[ \t]*')
RE_BLOCKQUOTE = re.compile(r'^[ \t]{0,3}>+[ \t]?')
RE_BULLET = re.compile(r'^[ \t]*[-*+•][ \t]+')
RE_ORDERED = re.compile(r'^[ \t]*\d{1,3}[.)][ \t]+')
RE_HRULE = re.compile(r'^[ \t]*([-*_=])[ \t]*(?:\1[ \t]*){2,}$')
RE_BOLD = re.compile(r'\*\*(.+?)\*\*|__(.+?)__', re.S)
# Bounded to one line and 200 characters. With re.S and an unbounded .*?, every
# unpaired "_" (dotted attribute access, snake_case) rescanned to end of file,
# which cost 2.6 s on a 166 KB paste — on the GTK main thread.
RE_ITALIC = re.compile(r'(?<!\w)([*_])([^\s*_][^\n*_]{0,200})\1(?!\w)')
RE_CODE_SPAN = re.compile(r'`([^`]+)`')
RE_NUM_RANGE = re.compile(r'(\d)\s*[–—]\s*(\d)')
# [ \t] not \s: \s eats the blank line, so an em-dash attribution at the start
# of a paragraph silently merged into the paragraph above it.
RE_DASH = re.compile(r'[ \t]*[–—―][ \t]*')
RE_PARA_BREAK = re.compile(r'\n[ \t]*\n+')
RE_MULTI_PUNCT = re.compile(r'([.!?,;:])\1{1,}')
# [ \t] not \s: matching newlines here closed up the blank line between
# paragraphs whenever the next one opened with punctuation.
RE_SPACE_PUNCT = re.compile(r'[ \t]+([.!?,;:])')
# CJK sentences carry no spaces, so the ASCII splitter never sees a boundary.
RE_CJK_STOP = re.compile(r'([。！？])(?=\S)')


RE_KEY_SEP = re.compile(r'[_\-]+')
RE_KEY_CAMEL = re.compile(r'(?<=[a-z0-9])(?=[A-Z])')


def _humanise_key(key):
    """updated_at -> "updated at", createdAt -> "created at"."""
    text = RE_KEY_SEP.sub(' ', str(key))
    text = RE_KEY_CAMEL.sub(' ', text)
    return ' '.join(text.split()).lower()


def _json_scalar(value):
    if isinstance(value, bool):
        return 'true' if value else 'false'
    if value is None:
        return 'null'
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return value.strip() or 'empty'
    return None                                   # a container, not a scalar


def _walk_json(node, prefix, out):
    if isinstance(node, dict):
        for key, value in node.items():
            name = (prefix + ' ' + _humanise_key(key)).strip()
            scalar = _json_scalar(value)
            if scalar is not None:
                out.append('%s is %s.' % (name, scalar))
            elif isinstance(value, list) and value and all(
                    _json_scalar(v) is not None for v in value):
                out.append('%s: %s.' % (name, ', '.join(
                    _json_scalar(v) for v in value)))
            elif not value:
                out.append('%s is empty.' % name)
            else:
                _walk_json(value, name, out)
    elif isinstance(node, list):
        for i, value in enumerate(node, 1):
            label = '%s %d' % (prefix or 'item', i)
            scalar = _json_scalar(value)
            if scalar is not None:
                out.append('%s is %s.' % (label, scalar))
            else:
                _walk_json(value, label, out)
    else:
        scalar = _json_scalar(node)
        if scalar is not None:
            out.append('%s is %s.' % (prefix or 'value', scalar))


def json_to_prose(text):
    """Render a JSON selection as sentences, or None if it is not JSON.

    Read literally, JSON is punctuation soup: espeak drops the braces and
    quotes and emits keys and values as one undifferentiated stream, with no
    sentence stop anywhere, so the whole blob also becomes a single passage
    that cannot be skipped through.
    """
    stripped = text.strip()
    if not stripped:
        return None

    records = []
    if stripped[0] in '{[':
        try:
            records = [json.loads(stripped)]
        except ValueError:
            records = []
    if not records:
        # JSON lines: one object per line, as emitted by structured loggers.
        lines = [l.strip() for l in stripped.splitlines() if l.strip()]
        if not lines or not all(l[0] in '{[' for l in lines):
            return None
        try:
            records = [json.loads(l) for l in lines]
        except ValueError:
            return None

    out = []
    for i, record in enumerate(records, 1):
        if len(records) > 1:
            out.append('Record %d.' % i)
        _walk_json(record, '', out)
    return '\n'.join(out) if out else None


def _speak_url(match):
    """Replace a URL with "link", handing back any punctuation that ended the
    sentence rather than the URL. Without this, "See https://x.com. Then we
    left." lost its full stop and ran the two sentences together."""
    url = match.group(0).rstrip('>')
    kept = url.rstrip(URL_TRAIL)
    return ' link ' + url[len(kept):]


def speech_punct(text):
    """Punctuation fixes that help espeak regardless of the source format.

    Markdown emphasis is stripped here rather than in normalize() so that the
    tidy path gets it too: Haiku's output never passes through normalize(), so
    any bold it emits was previously read out with its asterisks intact.
    """
    text = RE_BOLD.sub(lambda m: m.group(1) or m.group(2), text)
    text = RE_ITALIC.sub(r'\2', text)
    text = RE_CODE_SPAN.sub(r'\1', text)
    text = RE_TIMES.sub(' times ', text)
    text = RE_STRAY_STAR.sub('', text)
    text = RE_NUMBER_SIGN.sub(' number ', text)
    text = RE_NUM_RANGE.sub(r'\1 to \2', text)
    text = RE_YEAR_RANGE.sub(r'\1 to \2', text)
    text = RE_DASH.sub(', ', text)
    # Before RE_MULTI_PUNCT, which would otherwise reduce "..." to a full stop
    # and split the sentence there.
    text = RE_ELLIPSIS.sub(', ', text)
    text = RE_CJK_STOP.sub(r'\1 ', text)
    for src, dst in PUNCT_MAP.items():
        text = text.replace(src, dst)
    text = RE_MULTI_PUNCT.sub(r'\1', text)
    text = RE_SPACE_PUNCT.sub(r'\1', text)
    return text


def normalize(text):
    """Turn arbitrary copied text into clean prose the engine can read aloud."""
    # Before anything else: a JSON selection is restructured into sentences
    # rather than having its punctuation stripped and its content run together.
    as_prose = json_to_prose(text)
    if as_prose is not None:
        text = as_prose

    for src, dst in PRE_NFKC.items():
        text = text.replace(src, dst)
    text = unicodedata.normalize('NFKC', text)
    text = text.translate(ZERO_WIDTH)
    text = text.replace('\r\n', '\n').replace('\r', '\n')

    # Dropping fenced blocks is right when they sit among prose, but a whole
    # selection wrapped in one fence — an LLM answer, a pasted chat message —
    # would otherwise normalize to nothing at all.
    without_fences = RE_CODE_FENCE.sub('\n\n', text)
    if re.search(r'[^\W_]', without_fences):
        text = without_fences
    else:
        text = RE_CODE_FENCE_BODY.sub(lambda m: '\n' + m.group(1) + '\n', text)

    # De-hyphenate before unwrapping, or the line break disappears first.
    text = RE_HYPHEN_BREAK.sub(r'\1\2', text)
    text = RE_MD_IMAGE.sub(' ', text)
    text = RE_MD_LINK.sub(r'\1', text)
    text = RE_URL.sub(_speak_url, text)
    text = RE_FOOTNOTE.sub('', text)

    # Line-level structure. Only lines that carried a structural marker get
    # terminal punctuation; adding it to every line would put a full stop at
    # the end of each line of a hard-wrapped paragraph.
    lines = []
    for raw in text.split('\n'):
        line = raw.strip()
        if not line or RE_HRULE.match(line):
            lines.append('')
            continue

        structural = False
        for pattern in (RE_HEADING, RE_BLOCKQUOTE, RE_ORDERED, RE_BULLET):
            new = pattern.sub('', line)
            if new != line:
                structural = True
                line = new.strip()

        if line.startswith('|') or line.endswith('|'):
            line = line.strip('|').replace('|', ', ').strip()
            structural = True

        # Drop anything with no letters or digits left, such as a markdown
        # table's separator row, which would otherwise be read as dashes.
        if not re.search(r'[^\W_]', line):
            lines.append('')
            continue
        if structural and line[-1] not in '.!?:;,':
            line += '.'
        lines.append(line)
    text = '\n'.join(lines)

    # Emphasis and code spans are handled inside speech_punct, which both this
    # path and the tidy path go through.
    text = speech_punct(text)

    # Unwrap: blank lines separate paragraphs, single newlines are soft wraps.
    # lstrip: a paragraph opening with a dash or bullet leaves the replacement
    # punctuation stranded at the front ("— Author" becomes ", Author").
    paragraphs = [' '.join(p.split()).lstrip(' ,;:.') for p in RE_PARA_BREAK.split(text)]
    paragraphs = [p for p in paragraphs if p and re.search(r'\w', p)]
    return '\n\n'.join(paragraphs).strip()


# --------------------------------------------------------------------------
# Terminal-likeness detection
#
# Decides whether text is worth sending through the rewrite stage. Prose from
# a browser scores near zero; a shell paste scores high.
# --------------------------------------------------------------------------

RE_ANSI = re.compile(r'\x1b\[[0-9;?]*[A-Za-z]')
# Bare ">" is deliberately absent: it is a markdown blockquote and a quoted
# email far more often than it is a shell prompt.
RE_PROMPT = re.compile(
    r'^[ \t]*(?:'
    r'\[[^\]\n]{1,40}\][$#>]|'                     # [shaun@desk ~]$
    r'PS [A-Za-z]:\\[^\n>]*>|'                     # PowerShell
    r'[\w.-]+@[\w.-]+[^\n]{0,40}?[$#>❯»]|'         # shaun@desk ~/x >
    r'[~/][\w./~-]*[^\n]{0,40}?[$#>❯»]|'           # ~/Projects/x >
    r'[$❯»]'                                       # bare $ / ❯ / »
    r')[ \t]', re.M)
# Stack traces are prime material for the rewrite stage and carry none of the
# other signals — no prompt, no paths with slashes, ordinary sentence case.
RE_TRACE = re.compile(
    r'^[ \t]*(?:Traceback \(most recent call last\)|File "[^"\n]+", line \d+|'
    r'at [\w$.]+\(|[\w./-]+:\d+:\d+)|\b\w+(?:Error|Exception)\b[ \t]*:')
RE_LINENO = re.compile(r'^\s*\d+[:\t]')
RE_PATHY = re.compile(r'(?:^|\s)[~.]?(?:/[\w.-]+){2,}')
RE_BOX = re.compile(r'[─-╿▀-▟]')
RE_COLUMNS = re.compile(r'\S {3,}\S')
RE_LOGLEVEL = re.compile(r'\b(?:DEBUG|INFO|WARN|WARNING|ERROR|FATAL|TRACE)\b')
RE_TIMESTAMP = re.compile(r'\b\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}')
# A real hash mixes letters and digits. Without the guards this matched any
# 7-digit number ("1450000") and English words spelled in hex ("defaced").
RE_HASH = re.compile(r'\b(?![0-9]+\b)(?![a-f]+\b)[0-9a-f]{7,40}\b')
# A lone "(" or ";" appears constantly in ordinary prose, so neither counts.
RE_CODEISH = re.compile(
    r'[{}]|\(\)|\[\]|=>|::|;[ \t]*$|'
    r'\b(?:return|import|def|function|const|let|var|class|else|null|true|false)\b')


def terminal_score(text):
    """Rough 0-1 estimate of how much this looks like terminal output."""
    lines = [line for line in text.split('\n') if line.strip()]
    if not lines:
        return 0.0
    if RE_ANSI.search(text):
        return 1.0

    codey = 0
    for line in lines:
        hits = 0.0
        if RE_PROMPT.match(line):
            hits += 2
        if RE_LINENO.match(line):
            hits += 1
        if RE_PATHY.search(line):
            hits += 1
        if RE_BOX.search(line):
            hits += 1
        if RE_COLUMNS.search(line):
            hits += 1
        if RE_LOGLEVEL.search(line):
            hits += 1
        if RE_TIMESTAMP.search(line):
            hits += 1
        if RE_HASH.search(line):
            hits += 1
        if RE_CODEISH.search(line):
            hits += 1
        if RE_TRACE.search(line):
            hits += 2
        if line.rstrip()[-1] not in '.!?:"\')':
            hits += 0.5
        if hits >= 1.5:
            codey += 1

    score = codey / len(lines)
    # A shell prompt or a traceback header is decisive on its own; a short
    # paste containing one would otherwise be diluted by its output lines.
    if RE_PROMPT.search(text) or RE_TRACE.search(text):
        score = max(score, 0.6)
    return min(1.0, score)


# --------------------------------------------------------------------------
# Sentence splitting and passage grouping
# --------------------------------------------------------------------------

ABBREV = {
    'mr', 'mrs', 'ms', 'dr', 'prof', 'sr', 'jr', 'st', 'vs', 'etc', 'eg',
    'ie', 'ca', 'approx', 'inc', 'ltd', 'co', 'corp', 'dept', 'est',
    'al', 'cf', 'ed', 'repr', 'trans', 'univ', 'assn',
    'jan', 'feb', 'mar', 'apr', 'jun', 'jul', 'aug', 'sep', 'sept', 'oct',
    'nov', 'dec', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun',
}

# These are abbreviations only when a number follows. Without the check, the
# ordinary sentence "No." gets glued onto the sentence after it.
NUMERIC_ABBREV = {'no', 'nos', 'vol', 'vols', 'pp', 'fig', 'figs', 'ch', 'sec'}

RE_SENT_SPLIT = re.compile(r'(?<=[.!?])["\')\]]*\s+')
RE_CLAUSE_SPLIT = re.compile(r'(?<=[,;:])\s+')
RE_SENT_BOUNDARY = re.compile(r'[.!?]["\')\]]*\s+')


def _ends_in_abbreviation(text, following=''):
    match = re.search(r'([A-Za-z0-9.]+)\.["\')\]]*$', text)
    if not match:
        return False
    token = match.group(1).rstrip('.').lower()
    if not token:
        return False
    if token in NUMERIC_ABBREV:
        # Nothing after it yet: assume more is coming rather than split early.
        return True if not following.strip() else bool(re.match(r'\s*\d', following))
    # Single letters are initials. Bare digits are deliberately NOT treated as
    # list numbering: RE_ORDERED already strips real list markers, and matching
    # here glued every sentence ending in a number to the one after it
    # ("Sales rose to 42. That was good news." became one utterance).
    return token in ABBREV or len(token) == 1


def split_sentences(paragraph):
    sentences = []
    for part in RE_SENT_SPLIT.split(paragraph):
        part = part.strip()
        if not part:
            continue
        if sentences and _ends_in_abbreviation(sentences[-1], part):
            sentences[-1] = sentences[-1] + ' ' + part
        else:
            sentences.append(part)
    return sentences


def _split_long_sentence(sentence):
    # The character test matters as much as the word test: text with no spaces
    # counts as a single word and would otherwise return here unbounded.
    if len(sentence.split()) <= MAX_WORDS and len(sentence) <= MAX_CHARS:
        return [sentence]

    out, current = [], []
    for clause in RE_CLAUSE_SPLIT.split(sentence):
        if current and len(' '.join(current).split()) + len(clause.split()) > CLAUSE_WORDS:
            out.append(' '.join(current))
            current = []
        current.append(clause)
    if current:
        out.append(' '.join(current))

    # Any clause still oversized gets a hard split so no passage is unbounded.
    final = []
    for piece in out:
        words = piece.split()
        if len(words) <= MAX_WORDS:
            final.append(piece)
        else:
            for i in range(0, len(words), CLAUSE_WORDS):
                final.append(' '.join(words[i:i + CLAUSE_WORDS]))
    return [f for c in final for f in _bound_chars(c) if f.strip()]


def _bound_chars(piece):
    """Bound a passage by characters as well as words.

    A base64 blob or CJK text has no spaces, so it counts as one word and slips
    past every word-based limit. Piper's cost is superlinear in input length,
    and as passage zero such a blob delays the first audio indefinitely.
    """
    if len(piece) <= MAX_CHARS:
        return [piece]
    return [piece[i:i + MAX_CHARS] for i in range(0, len(piece), MAX_CHARS)]


def build_passages(text):
    """One passage per sentence, so skipping moves a sentence at a time.

    Splitting this finely costs an extra piper-tts invocation per sentence
    (~0.15 s of model load), against roughly 4.7 s of audio produced, so
    synthesis still runs far ahead of playback.
    """
    passages = []
    for paragraph in text.split('\n\n'):
        for sentence in split_sentences(paragraph):
            passages.extend(_split_long_sentence(sentence))

    # piper-tts treats each input line as a separate utterance, so a passage
    # must be exactly one line.
    return [' '.join(p.split()) for p in passages if p.strip()]


# --------------------------------------------------------------------------
# Rewrite stage (OpenRouter, streaming)
# --------------------------------------------------------------------------

def tidy_available():
    return bool(openrouter.key())


def _text_blocks(text, max_words):
    blocks, current, count = [], [], 0
    for line in text.split('\n'):
        words = line.split()
        # A single very long line — a web or PDF paste that arrives without
        # newlines — must still be broken up, or the whole document becomes one
        # oversized request whose reply is silently truncated at max_tokens.
        pieces = ([' '.join(words[i:i + max_words])
                   for i in range(0, len(words), max_words)] if words else [line])
        for piece in pieces:
            length = len(piece.split())
            if current and count + length > max_words:
                blocks.append('\n'.join(current))
                current, count = [], 0
            current.append(piece)
            count += length
    if current:
        blocks.append('\n'.join(current))
    return [b for b in blocks if b.strip()]


def _drain_sentences(buf):
    """Pull complete sentences out of a streaming buffer."""
    sentences, last = [], 0
    for match in RE_SENT_BOUNDARY.finditer(buf):
        candidate = buf[last:match.end()].strip()
        if not candidate or _ends_in_abbreviation(candidate, buf[match.end():]):
            continue
        sentences.append(candidate)
        last = match.end()
    return sentences, buf[last:]


def _stream_completion(system, user, stop_event):
    """Yield content deltas from one OpenRouter chat completion.

    Returns (generator). The final element yielded is a ('finish', reason)
    tuple so the caller can tell a complete rewrite from a truncated one --
    otherwise the tail of a document just disappears silently.

    Reasoning is excluded rather than merely set low: reasoning tokens arrive
    before any content and would delay the first spoken sentence, which is the
    one number this whole design optimises for.
    """
    return openrouter.stream_chat({
        'model': TIDY_MODEL,
        'max_tokens': 4096,
        'reasoning': {'effort': 'low', 'exclude': True},
        'messages': [{'role': 'system', 'content': system},
                     {'role': 'user', 'content': user}],
    }, timeout=TIDY_TIMEOUT, title='lastshell reader', stop_event=stop_event)


class TidyWorker(threading.Thread):
    """Streams text through a rewrite model, emitting passages early."""

    def __init__(self, raw_text, epoch, on_passage, on_done, on_error, on_status):
        super().__init__(daemon=True)
        self.raw_text = raw_text
        # Stamped on every callback. Threads are stopped but never joined, so
        # work queued just before a hotkey re-press would otherwise land on the
        # next document; the window drops any callback from a stale epoch.
        self.epoch = epoch
        self.on_passage = on_passage
        self.on_done = on_done
        self.on_error = on_error
        self.on_status = on_status
        self.stop_event = threading.Event()
        self.emitted = 0

    def stop(self):
        self.stop_event.set()

    def _add(self, sentence):
        # Collapse after, not before: speech_punct pads its replacements with
        # spaces so they cannot run into the neighbouring word.
        sentence = ' '.join(speech_punct(sentence).split())
        if not sentence:
            return
        # Emitted as soon as the sentence is complete, so Piper starts on it
        # while Haiku is still writing the rest of the block.
        for piece in _split_long_sentence(sentence):
            if self.stop_event.is_set():
                return
            self.emitted += 1
            GLib.idle_add(self.on_passage, self.epoch, piece)

    def run(self):
        if not openrouter.key():
            GLib.idle_add(self.on_error, self.epoch,
                          'no OpenRouter key (%s)' % openrouter.KEY_FILE)
            return

        blocks = _text_blocks(self.raw_text, TIDY_BLOCK_WORDS)
        for number, block in enumerate(blocks, 1):
            if self.stop_event.is_set():
                return
            GLib.idle_add(self.on_status, self.epoch,
                          'rewriting %d/%d' % (number, len(blocks)))
            buf = ''
            try:
                for kind, value in _stream_completion(TIDY_SYSTEM, block,
                                                      self.stop_event):
                    if self.stop_event.is_set():
                        return
                    if kind == 'text':
                        buf += value
                        sentences, buf = _drain_sentences(buf)
                        for sentence in sentences:
                            self._add(sentence)
                        continue
                    # Otherwise a truncated rewrite is indistinguishable from
                    # a complete one and the tail of the document just
                    # disappears.
                    if value == 'length':
                        GLib.idle_add(self.on_status, self.epoch,
                                      'rewrite truncated, some text skipped')
            except openrouter.OpenRouterError as exc:
                GLib.idle_add(self.on_error, self.epoch, str(exc)[:200])
                return
            except Exception as exc:
                if self.stop_event.is_set():
                    return
                GLib.idle_add(self.on_error, self.epoch, '%s: %s'
                              % (type(exc).__name__, str(exc)[:160]))
                return
            if buf.strip() and not self.stop_event.is_set():
                self._add(buf)
        if not self.stop_event.is_set():
            GLib.idle_add(self.on_done, self.epoch)


# --------------------------------------------------------------------------
# Voices
# --------------------------------------------------------------------------

class Voice:
    """A selectable voice from either engine.

    A piper voice is a model file rendered by a subprocess; a kokoro voice is
    one style inside a single shared model held in this process.
    """

    def __init__(self, engine, key, label, path=None, style=None):
        self.engine = engine
        self.key = key
        self.label = label
        self.path = path      # piper only
        self.style = style    # kokoro only

    @classmethod
    def from_piper(cls, path):
        stem = path.name[:-len('.onnx')]
        parts = stem.split('-')
        label = ('%s (%s, %s)' % (parts[1], parts[2], parts[0])
                 if len(parts) >= 3 else stem)
        return cls('piper', stem, label, path=path)

    @classmethod
    def from_kokoro(cls, style):
        who = KOKORO_SPEAKERS.get(style[:2], style[:2])
        name = style[3:] or style
        return cls('kokoro', 'kokoro-' + style,
                   '%s (kokoro, %s)' % (name, who), style=style)


class KokoroEngine:
    """One Kokoro model, loaded once and kept for the life of the process.

    piper pays a full model load per sentence because it is a separate binary.
    Holding kokoro in-process removes that cost entirely, which is most of the
    per-sentence time at these lengths — measured 33x realtime on CUDA against
    piper's 6x.
    """

    _lock = threading.Lock()
    _model = None
    _failed = False

    @classmethod
    def available(cls):
        return KOKORO_MODEL.exists() and KOKORO_VOICES_BIN.exists()

    @classmethod
    def styles(cls):
        """Voice names straight out of the 27 MB style bank, so building the
        dropdown never touches the 311 MB model."""
        try:
            import numpy as np
            with np.load(str(KOKORO_VOICES_BIN)) as data:
                return sorted(data.files)
        except Exception:
            return []

    @classmethod
    def get(cls):
        with cls._lock:
            if cls._model is not None or cls._failed:
                return cls._model
            try:
                import onnxruntime as ort
                from kokoro_onnx import Kokoro
                ort.set_default_logger_severity(3)
                # Name CUDA explicitly: left to itself ORT tries TensorRT
                # first, fails noisily, and falls back.
                have = ort.get_available_providers()
                providers = [p for p in ('CUDAExecutionProvider',) if p in have]
                providers.append('CPUExecutionProvider')
                session = ort.InferenceSession(str(KOKORO_MODEL),
                                               providers=providers)
                cls._model = Kokoro.from_session(session, str(KOKORO_VOICES_BIN))
            except Exception:
                cls._failed = True
            return cls._model

    @classmethod
    def synth(cls, text, style, path):
        model = cls.get()
        if model is None:
            raise RuntimeError('kokoro model could not be loaded')
        import soundfile as sf
        samples, rate = model.create(text, voice=style, speed=1.0,
                                     lang=KOKORO_LANG)
        sf.write(str(path), samples, rate)


def discover_voices(allow=None, keep=()):
    """Find usable voices under both roots.

    `allow` is an optional list of voice keys from the config. The packaged
    piper-voices set is 26 entries deep and most of it is never wanted, so the
    dropdown shows only the listed keys when one is configured. Anything in
    `keep` (the default and the currently selected voice) survives the filter
    regardless, so a stale config can never leave the list empty.
    """
    voices, seen = [], set()
    for root in VOICE_ROOTS:
        if not root.is_dir():
            continue
        for onnx in sorted(root.rglob('*.onnx')):
            if not Path(str(onnx) + '.json').exists():
                continue
            voice = Voice.from_piper(onnx)
            if voice.key in seen:
                continue
            seen.add(voice.key)
            voices.append(voice)

    if KokoroEngine.available():
        for style in KokoroEngine.styles():
            voice = Voice.from_kokoro(style)
            if voice.key not in seen:
                seen.add(voice.key)
                voices.append(voice)

    if allow:
        wanted = set(allow) | {k for k in keep if k}
        filtered = [v for v in voices if v.key in wanted]
        if filtered:
            voices = filtered
    voices.sort(key=lambda v: (v.key != DEFAULT_VOICE, v.label))
    return voices


def wav_duration(path):
    try:
        with wave.open(str(path)) as handle:
            rate = handle.getframerate()
            return handle.getnframes() / rate if rate else 0.0
    except Exception:
        return 0.0


# --------------------------------------------------------------------------
# Settings
# --------------------------------------------------------------------------

def load_config():
    # once: carry the GTK app's settings (voice, speed, tidy, the voice
    # shortlist) over to lastshell's config home
    if not CONFIG_PATH.exists() and OLD_CONFIG_PATH.exists():
        try:
            CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
            os.replace(OLD_CONFIG_PATH, CONFIG_PATH)
            OLD_CONFIG_PATH.parent.rmdir()
        except OSError:
            pass
    try:
        data = json.loads(CONFIG_PATH.read_text())
    except Exception:
        return {}
    # A file containing valid JSON that is not an object (null, a list, a bare
    # number) would otherwise crash the window constructor before it is shown.
    return data if isinstance(data, dict) else {}


def config_float(config, key, default):
    try:
        value = float(config.get(key, default))
    except (TypeError, ValueError):
        return default
    return value if value == value else default   # reject NaN


def save_config(changes):
    """Merge `changes` into whatever is on disk right now.

    The window reads its config once at startup. Writing the whole in-memory
    dict back on close would silently discard any edit made to the file while
    the window was open — which is exactly how a hand-edited `voices` list got
    reverted by closing a reader that had been opened before the edit.
    """
    try:
        CONFIG_PATH.parent.mkdir(parents=True, exist_ok=True)
        current = load_config()
        current.update(changes)
        CONFIG_PATH.write_text(json.dumps(current, indent=2))
    except OSError:
        pass


LOCK_NAME = '.lock'


def claim_workdir(path):
    """Take an exclusive lock held for the window's lifetime, so another
    instance's startup sweep can tell this directory is still in use."""
    try:
        fd = os.open(str(Path(path) / LOCK_NAME), os.O_CREAT | os.O_RDWR, 0o600)
        fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return fd
    except OSError:
        return None


def sweep_stale_workdirs():
    """Drop work directories left behind by an instance that was killed hard.

    Liveness is a held lock, not "does mpv answer". A running window whose mpv
    has died still owns its directory, and the previous socket probe would have
    deleted it out from under that window — taking its rendered audio with it.
    """
    now = time.time()
    for path in Path(tempfile.gettempdir()).glob('piper-reader-*'):
        if not path.is_dir():
            continue
        lock = path / LOCK_NAME
        if lock.exists():
            try:
                fd = os.open(str(lock), os.O_RDWR)
            except OSError:
                continue
            try:
                fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
                fcntl.flock(fd, fcntl.LOCK_UN)
            except OSError:
                continue                      # still held: live
            finally:
                os.close(fd)
        else:
            # Older layout, or a directory created moments ago by an instance
            # that has not claimed it yet.
            try:
                if now - path.stat().st_mtime < 60:
                    continue
            except OSError:
                continue
        shutil.rmtree(path, ignore_errors=True)


# --------------------------------------------------------------------------
# mpv JSON IPC
#
# Commands are fire-and-forget so the GTK main loop never blocks on the
# socket. State comes back through observed properties cached by the reader
# thread and sampled by a UI timer.
# --------------------------------------------------------------------------

PR_SET_PDEATHSIG = 1
try:
    _LIBC = ctypes.CDLL('libc.so.6', use_errno=True)
except OSError:
    _LIBC = None


def _die_with_parent():
    """mpv runs with --idle, so without this it outlives a crashed or killed
    parent forever and quietly holds the audio device."""
    if _LIBC is not None:
        _LIBC.prctl(PR_SET_PDEATHSIG, signal.SIGKILL, 0, 0, 0)


class MpvError(Exception):
    pass


class Mpv:
    def __init__(self, socket_path):
        self.socket_path = str(socket_path)
        self.properties = {}
        self.alive = True
        self._lock = threading.Lock()
        self._request_id = 0
        self._on_dead = None

        self.proc = subprocess.Popen(
            ['mpv', '--no-config', '--no-terminal', '--idle=yes', '--no-video',
             '--force-window=no', '--gapless-audio=yes',
             '--audio-pitch-correction=yes', '--keep-open=no', '--volume=100',
             '--ao=' + os.environ.get('PIPER_READER_AO', 'pipewire,pulse,alsa'),
             '--input-ipc-server=' + self.socket_path],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            preexec_fn=_die_with_parent)

        deadline = time.monotonic() + 10.0
        self.sock = None
        while time.monotonic() < deadline:
            if self.proc.poll() is not None:
                raise MpvError('mpv exited during startup')
            try:
                sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
                sock.connect(self.socket_path)
                self.sock = sock
                break
            except OSError:
                time.sleep(0.05)
        if self.sock is None:
            # The constructor is about to raise, so nothing will ever hold a
            # reference to this process; left alone it idles forever holding
            # the audio device.
            try:
                self.proc.kill()
            except Exception:
                pass
            raise MpvError('could not connect to the mpv IPC socket')

        threading.Thread(target=self._read_loop, daemon=True).start()
        for name in ('pause', 'playlist-pos', 'playlist-count', 'time-pos',
                     'duration', 'idle-active'):
            self.observe(name)

    def _send(self, payload):
        if not self.alive:
            return
        try:
            with self._lock:
                self.sock.sendall((json.dumps(payload) + '\n').encode())
        except OSError:
            self._mark_dead()

    def command(self, *args):
        with self._lock:
            self._request_id += 1
            rid = self._request_id
        self._send({'command': list(args), 'request_id': rid})

    def observe(self, name):
        with self._lock:
            self._request_id += 1
            rid = self._request_id
        self._send({'command': ['observe_property', rid, name],
                    'request_id': rid})

    def set_property(self, name, value):
        self.command('set_property', name, value)

    def get(self, name, default=None):
        value = self.properties.get(name, default)
        return default if value is None else value

    def _mark_dead(self):
        if self.alive:
            self.alive = False
            if self._on_dead:
                GLib.idle_add(self._on_dead)

    def _read_loop(self):
        buf = b''
        try:
            while True:
                data = self.sock.recv(65536)
                if not data:
                    break
                buf += data
                while b'\n' in buf:
                    line, buf = buf.split(b'\n', 1)
                    if not line.strip():
                        continue
                    try:
                        message = json.loads(line.decode('utf-8', 'replace'))
                    except ValueError:
                        continue
                    if message.get('event') == 'property-change':
                        self.properties[message.get('name')] = message.get('data')
        except OSError:
            pass
        finally:
            self._mark_dead()

    def shutdown(self):
        # Send quit BEFORE clearing `alive`, or _send's own guard swallows it,
        # mpv --idle never exits, and the wait below burns its full timeout on
        # the GTK main thread — a visible freeze on every teardown.
        try:
            self._send({'command': ['quit']})
        except Exception:
            pass
        self.alive = False
        try:
            self.proc.wait(timeout=2)
        except Exception:
            try:
                self.proc.kill()
                self.proc.wait(timeout=1)
            except Exception:
                pass
        # Closed last: the reader thread is blocked in recv() on this fd, and
        # closing it early risks the number being recycled by the next Mpv.
        try:
            self.sock.close()
        except Exception:
            pass


# --------------------------------------------------------------------------
# Synthesis producer
# --------------------------------------------------------------------------

class Producer(threading.Thread):
    """Renders passages to WAV ahead of the playhead and appends them to mpv.

    The passage list may still be growing while this runs, because the tidy
    stage streams. The loop therefore waits at the end of the list rather than
    finishing, until the list is marked complete.
    """

    def __init__(self, passages, voice, workdir, start_index, epoch,
                 playhead, is_complete, on_ready, on_done, on_error):
        super().__init__(daemon=True)
        self.passages = passages
        self.voice = voice
        self.workdir = Path(workdir)
        self.start_index = start_index
        # Bumped for every producer, including the restart after a voice
        # change, so a WAV rendered in the previous voice cannot be appended
        # to the playlist after the switch.
        self.epoch = epoch
        self.playhead = playhead
        self.is_complete = is_complete
        self.on_ready = on_ready
        self.on_done = on_done
        self.on_error = on_error
        self.stop_event = threading.Event()
        self._proc = None

    def stop(self):
        self.stop_event.set()
        proc = self._proc
        if proc and proc.poll() is None:
            try:
                proc.kill()
            except Exception:
                pass

    def run(self):
        index = self.start_index
        while not self.stop_event.is_set():
            if index >= len(self.passages):
                if self.is_complete():
                    break
                if self.stop_event.wait(0.15):
                    return
                continue

            # Stay within LOOKAHEAD of the playhead so a long document does
            # not render 28 minutes of audio into /tmp up front.
            while (index - self.playhead()) > LOOKAHEAD:
                if self.stop_event.wait(0.25):
                    return

            path = self.workdir / ('%05d.wav' % index)
            try:
                if self.voice.engine == 'kokoro':
                    # In-process: no per-sentence model load, so nothing to
                    # kill either. stop_event is honoured between sentences,
                    # which at ~1 s each is responsive enough.
                    KokoroEngine.synth(self.passages[index],
                                       self.voice.style, path)
                    code, err = 0, b''
                else:
                    self._proc = subprocess.Popen(
                        [PIPER, '-m', str(self.voice.path), '-f', str(path), '-q'],
                        stdin=subprocess.PIPE,
                        stdout=subprocess.DEVNULL,
                        stderr=subprocess.PIPE)
                    _, err = self._proc.communicate(
                        self.passages[index].encode('utf-8') + b'\n')
                    code = self._proc.returncode
            except Exception as exc:
                if not self.stop_event.is_set():
                    GLib.idle_add(self.on_error, self.epoch, str(exc))
                return
            finally:
                self._proc = None

            if self.stop_event.is_set():
                return
            if code != 0 or not path.exists():
                detail = err.decode('utf-8', 'replace').strip().splitlines()
                message = detail[-1] if detail else 'piper-tts failed (%s)' % code
                GLib.idle_add(self.on_error, self.epoch, message)
                return

            # Duration is read before the stop check so the callback carries no
            # file access of its own.
            duration = wav_duration(path)
            if self.stop_event.is_set():
                return
            GLib.idle_add(self.on_ready, self.epoch, index, str(path), duration)
            index += 1

        if not self.stop_event.is_set():
            GLib.idle_add(self.on_done, self.epoch)


# --------------------------------------------------------------------------
# Clipboard
# --------------------------------------------------------------------------

def grab_text():
    """Primary selection first, then the clipboard."""
    for args in (['wl-paste', '--primary', '--no-newline', '-t', 'text'],
                 ['wl-paste', '--no-newline', '-t', 'text']):
        try:
            result = subprocess.run(args, capture_output=True, timeout=5)
        except (OSError, subprocess.TimeoutExpired):
            continue
        if result.returncode == 0:
            text = result.stdout.decode('utf-8', 'replace').strip()
            if text:
                return text
    return ''


def notify(summary, body=''):
    if shutil.which('notify-send'):
        subprocess.Popen(['notify-send', '-a', 'Piper Reader', summary, body],
                         stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def format_time(seconds):
    seconds = max(0, int(seconds))
    hours, rest = divmod(seconds, 3600)
    minutes, secs = divmod(rest, 60)
    if hours:
        return '%d:%02d:%02d' % (hours, minutes, secs)
    return '%d:%02d' % (minutes, secs)


# --------------------------------------------------------------------------
# Headless controller (was ReaderWindow)
# --------------------------------------------------------------------------
#
# stdin, one command per line:
#   read                 grab the primary selection (else the clipboard) and read it
#   toggle | next | prev | stop | quit
#   speed <x>            0.5 .. 3.0
#   voice <key>          a key from the `voices` event
#   tidy <Off|Auto|Always>
#
# stdout, one event per line, each `<name> <json>`:
#   voices  [{key, label}]       once at start
#   config  {voice, speed, tidy, tidy_available}
#   state   {...}                on change; the shell renders this as-is
#   notice  "text"               a passing message (the GTK app's toasts)

def emit(name, value):
    sys.stdout.write('%s %s\n' % (name, json.dumps(value)))
    sys.stdout.flush()


class Reader:
    def __init__(self, loop):
        self.loop = loop
        self.config = load_config()
        self.voices = discover_voices(self.config.get('voices'),
                                      keep=(DEFAULT_VOICE, self.config.get('voice')))
        self.voice = self._initial_voice()
        self.speed = config_float(self.config, 'speed', 1.0)
        mode = self.config.get('tidy', 'Auto')
        self.tidy_mode = mode if mode in TIDY_MODES else 'Auto'
        self.passages = []
        self.durations = {}
        self.passages_complete = True
        self.producer = None
        self.tidy = None
        self.tidy_note = ''
        self.mpv = None
        self.render_complete = False
        self.raw_text = ''
        self.fault = ''
        self.message = ''        # shown in place of a passage (errors, "rewriting")
        self.doc_epoch = 0
        self.prod_epoch = 0
        self.appended = 0
        self.workdir = Path(tempfile.mkdtemp(prefix='piper-reader-'))
        self._lock_fd = claim_workdir(self.workdir)
        self._tick_id = 0
        self._save_id = 0
        self._last_state = None
        atexit.register(shutil.rmtree, str(self.workdir), True)
        for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
            unix_signal_add(GLib.PRIORITY_DEFAULT, sig, self.quit)

        emit('voices', [{'key': v.key, 'label': v.label} for v in self.voices])
        self._emit_config()
        self._emit_state()

    def _initial_voice(self):
        if not self.voices:
            return None
        saved = self.config.get('voice')
        for voice in self.voices:
            if voice.key == saved:
                return voice
        return self.voices[0]

    def _emit_config(self):
        emit('config', {'voice': self.voice.key if self.voice else '',
                        'speed': round(self.speed, 2), 'tidy': self.tidy_mode,
                        'tidy_available': tidy_available()})

    def _notice(self, text):
        emit('notice', text)

    # -- commands ----------------------------------------------------------

    def command(self, line):
        word, _, arg = line.strip().partition(' ')
        if word == 'read':
            text = grab_text()
            if text:
                self.load_text(text)
            else:
                self._notice('Nothing selected or copied')
        elif word == 'toggle':
            if self.mpv:
                self.mpv.set_property('pause', not bool(self.mpv.get('pause', False)))
        elif word == 'next':
            if self.mpv:
                self.mpv.command('playlist-next', 'weak')
        elif word == 'prev':
            if self.mpv:
                if float(self.mpv.get('time-pos', 0.0) or 0.0) > 3.0:
                    self.mpv.command('seek', 0, 'absolute')
                else:
                    self.mpv.command('playlist-prev', 'weak')
        elif word == 'stop':
            self.stop()
        elif word == 'speed':
            try:
                self.speed = max(0.5, min(3.0, float(arg)))
            except ValueError:
                return
            if self.mpv:
                self.mpv.set_property('speed', self.speed)
            # a drag sends a step per pixel; write the file once it settles
            if self._save_id:
                GLib.source_remove(self._save_id)
            self._save_id = GLib.timeout_add(800, self._save_speed)
            self._emit_config()
        elif word == 'voice':
            self.set_voice(arg)
        elif word == 'tidy':
            if arg in TIDY_MODES:
                self.tidy_mode = arg
                save_config({'tidy': arg})
                self._emit_config()
        elif word == 'quit':
            self.quit()
        self._emit_state()

    def _save_speed(self):
        self._save_id = 0
        save_config({'speed': round(self.speed, 2)})
        return GLib.SOURCE_REMOVE

    def stop(self):
        self._teardown_playback()
        self.doc_epoch += 1
        self.passages = []
        self.durations = {}
        self.message = ''
        self.fault = ''
        self.tidy_note = ''
        self._set_ticking(False)

    def quit(self):
        if self._save_id:
            GLib.source_remove(self._save_id)
            self._save_speed()
        self._teardown_playback()
        shutil.rmtree(self.workdir, ignore_errors=True)
        self.loop.quit()
        return GLib.SOURCE_REMOVE

    # -- document lifecycle ------------------------------------------------

    def load_text(self, raw_text):
        """Replace whatever is playing with a new document."""
        self._teardown_playback()
        self.doc_epoch += 1
        self.durations = {}
        self.appended = 0
        self.render_complete = False
        self.fault = ''
        self.message = ''
        self.raw_text = raw_text
        self.passages = []

        if not self.voice:
            self.message = ('No Piper voices were found under %s.'
                            % ' or '.join(str(r) for r in VOICE_ROOTS))
            return

        score = terminal_score(raw_text)
        words = len(raw_text.split())
        use_tidy = tidy_available() and (
            self.tidy_mode == 'Always' or
            (self.tidy_mode == 'Auto' and score >= TIDY_AUTO_THRESHOLD
             and words <= TIDY_AUTO_MAX_WORDS))

        try:
            self.mpv = Mpv(self.workdir / 'mpv.sock')
        except MpvError as exc:
            self.message = 'Could not start mpv: %s' % exc
            return
        self.mpv._on_dead = lambda epoch=self.doc_epoch: self._on_mpv_dead(epoch)
        self.mpv.set_property('speed', self.speed)

        if use_tidy:
            self.passages_complete = False
            self.tidy_note = 'rewriting'
            self.message = 'Rewriting for speech…'
            self.tidy = TidyWorker(raw_text, self.doc_epoch,
                                   self._on_tidy_passage,
                                   self._on_tidy_done, self._on_tidy_error,
                                   self._on_tidy_status)
            self.tidy.start()
        else:
            self._load_plain(raw_text)

        self._start_producer(0)
        self._set_ticking(True)

    def _load_plain(self, raw_text):
        # Fill in place: the Producer holds a reference to this list object.
        self.passages[:] = build_passages(normalize(raw_text))
        self.tidy_note = ''
        self.message = ''
        if not self.passages:
            self.passages_complete = True
            self.message = 'No readable text was found in the selection or clipboard.'
            self._notice('No readable text found')
            return
        self.passages_complete = True

    def _ensure_producer(self):
        if self.producer is not None and self.producer.is_alive():
            return
        if not self.passages or not self.mpv:
            return
        self._start_producer(len(self.durations))

    def _start_producer(self, start_index):
        self.prod_epoch += 1
        self.producer = Producer(
            self.passages, self.voice, self.workdir, start_index,
            self.prod_epoch, self._playhead, lambda: self.passages_complete,
            self._on_chunk_ready, self._on_render_done, self._on_producer_error)
        self.producer.start()

    def _teardown_playback(self):
        for worker in (self.tidy, self.producer):
            if worker:
                worker.stop()
        self.tidy = None
        self.producer = None
        if self.mpv:
            self.mpv._on_dead = None
            self.mpv.shutdown()
            self.mpv = None
        for stale in self.workdir.glob('*.wav'):
            try:
                stale.unlink()
            except OSError:
                pass

    def _playhead(self):
        return max(0, self._raw_playhead())

    def _raw_playhead(self):
        mpv = self.mpv
        if mpv is None:
            return 0
        return int(mpv.get('playlist-pos', 0) or 0)

    # -- worker callbacks (epoch-checked, as in the GTK app) -----------------

    def _on_tidy_passage(self, epoch, passage):
        if epoch != self.doc_epoch:
            return False
        self.passages.append(passage)
        self.message = ''
        return False

    def _on_tidy_done(self, epoch):
        if epoch != self.doc_epoch:
            return False
        self.tidy_note = ''
        if not self.passages:
            self._load_plain(self.raw_text)
            self._ensure_producer()
        else:
            self.passages_complete = True
        return False

    def _on_tidy_error(self, epoch, message):
        if epoch != self.doc_epoch:
            return False
        self.tidy_note = ''
        if not self.passages:
            self._notice('Tidy unavailable, reading raw text')
            self._load_plain(self.raw_text)
            self._ensure_producer()
        else:
            self.passages_complete = True
            self._notice('Tidy stopped: %s' % message)
        return False

    def _on_tidy_status(self, epoch, note):
        if epoch != self.doc_epoch:
            return False
        self.tidy_note = note
        return False

    def _on_chunk_ready(self, epoch, index, path, duration):
        if epoch != self.prod_epoch:
            return False
        self.durations[index] = duration
        if self.mpv and self.mpv.alive:
            self.mpv.command('loadfile', path, 'append-play')
            self.appended = index + 1
        return False

    def _on_render_done(self, epoch):
        if epoch != self.prod_epoch:
            return False
        self.render_complete = True
        return False

    def _on_producer_error(self, epoch, message):
        if epoch != self.prod_epoch:
            return False
        self.fault = 'Synthesis failed: %s' % message
        self._notice(self.fault)
        return False

    def _on_mpv_dead(self, epoch):
        if epoch != self.doc_epoch:
            return False
        for worker in (self.tidy, self.producer):
            if worker:
                worker.stop()
        self.tidy = None
        self.producer = None
        self.passages_complete = True
        self.render_complete = True
        self.fault = 'Playback stopped unexpectedly'
        self._notice(self.fault)
        return False

    def set_voice(self, key):
        voice = next((v for v in self.voices if v.key == key), None)
        if voice is None or voice is self.voice:
            return
        self.voice = voice
        self.config['voice'] = voice.key
        save_config({'voice': voice.key})
        self._emit_config()
        if not self.passages or not self.mpv:
            return
        # Re-render everything after the current passage in the new voice.
        position = self._playhead()
        if self.producer:
            self.producer.stop()
            self.producer = None
        for index in range(self.appended - 1, position, -1):
            self.mpv.command('playlist-remove', index)
        self.appended = min(self.appended, position + 1)
        for index in [i for i in self.durations if i > position]:
            del self.durations[index]
        self.render_complete = False
        self._start_producer(position + 1)

    # -- state ---------------------------------------------------------------

    def _set_ticking(self, on):
        # The tick only runs while a document is loaded: an idle engine waits
        # in the main loop and wakes for nothing.
        if on and not self._tick_id:
            self._tick_id = GLib.timeout_add(250, self._tick)
        elif not on and self._tick_id:
            GLib.source_remove(self._tick_id)
            self._tick_id = 0
        self._emit_state()

    def _tick(self):
        self._emit_state()
        return True

    def _state(self):
        if not self.mpv and not self.message:
            return {'active': False}
        total_passages = len(self.passages)
        raw_position = self._raw_playhead()
        finished = (raw_position < 0 and self.passages_complete
                    and self.render_complete and bool(self.durations))
        position = (total_passages - 1) if finished else max(0, raw_position)
        mpv = self.mpv
        time_pos = 0.0 if (finished or not mpv) else float(mpv.get('time-pos', 0.0) or 0.0)

        if finished:
            elapsed = sum(self.durations.values())
        else:
            elapsed = sum(self.durations.get(i, 0.0) for i in range(position)) + time_pos
        known = [d for d in self.durations.values() if d > 0]
        if known:
            average = sum(known) / len(known)
            total = sum(self.durations.values()) + average * (total_passages - len(self.durations))
        else:
            total = 0.0
        passage = self.message or (
            self.passages[position] if 0 <= position < total_passages else '')
        return {
            'active': True,
            'paused': bool(mpv.get('pause', False)) if mpv else True,
            'idle': bool(mpv.get('idle-active', False)) if mpv else True,
            'finished': finished,
            'position': min(position + 1, total_passages),
            'passages': total_passages,
            'complete': self.passages_complete,
            'settled': self.passages_complete and self.render_complete,
            'rendered': len(self.durations),
            # whole seconds: the shell repaints when these change, not 4x a second
            'elapsed': int(elapsed),
            'total': int(total),
            'passage': passage,
            'note': self.fault or self.tidy_note,
        }

    def _emit_state(self):
        state = self._state()
        if state != self._last_state:
            self._last_state = state
            emit('state', state)


def main():
    if not os.path.exists(PIPER):
        emit('notice', 'piper-tts is not installed at %s' % PIPER)
        return 1
    if not shutil.which('mpv'):
        emit('notice', 'mpv is not installed')
        return 1
    sweep_stale_workdirs()
    loop = GLib.MainLoop()
    reader = Reader(loop)

    # Raw reads, every complete line per wakeup: sys.stdin.readline() would
    # pull a burst ("tidy Always\nread\n") into Python's buffer and hand back
    # one line, leaving the rest where the fd watch can't see it until more
    # input arrives.
    pending = bytearray()

    def on_stdin(fd, condition):
        chunk = os.read(fd, 65536) if condition & GLib.IO_IN else b''
        if not chunk:
            reader.quit()     # EOF or hangup: the shell went away, stop speaking
            return False
        pending.extend(chunk)
        while b'\n' in pending:
            line, _, rest = bytes(pending).partition(b'\n')
            pending[:] = rest
            try:
                reader.command(line.decode('utf-8', 'replace'))
            except Exception as exc:  # one bad command must not kill the reader
                emit('notice', 'reader: %s' % exc)
        return True

    GLib.io_add_watch(sys.stdin.fileno(), GLib.PRIORITY_DEFAULT,
                      GLib.IO_IN | GLib.IO_HUP | GLib.IO_ERR, on_stdin)
    loop.run()
    return 0


if __name__ == '__main__':
    sys.exit(main())
