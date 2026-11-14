"""Upload validation: extension, magic bytes, size and the safe display name.

Contract "Uploads" + decision 06 #7:

* documents: `pdf, dwg, dxf, jpg, jpeg, png, doc, docx, xls, xlsx`, 25 MB;
* report photos: `jpg, jpeg, png, webp`, 10 MB;
* the declared extension must agree with the file's first bytes, so a `.pdf`
  holding HTML or an `.exe` renamed to `.png` never reaches storage;
* WebP is a RIFF container: `RIFF` at byte 0 **and** `WEBP` at byte 8, so an
  arbitrary RIFF file (a WAV, an AVI) or a truncated header is refused;
* DWG/DXF are CAD formats we never render: they are recognised by signature
  (`AC10`) / text and always served as a download (see the file views);
* a caller-supplied name never becomes a path — traversal names are refused and
  the stored name is a uuid (`models._storage_path`).

The size check runs on the spooled upload before anything is written, and
`settings.DATA_UPLOAD_MAX_MEMORY_SIZE` refuses an oversized body even earlier.
"""

from pathlib import PurePosixPath

from django.conf import settings

from ..projects.rules import RuleRefused
from . import rules

DOCUMENT_EXTENSIONS = (
    'pdf', 'dwg', 'dxf', 'jpg', 'jpeg', 'png', 'doc', 'docx', 'xls', 'xlsx',
)
PHOTO_EXTENSIONS = ('jpg', 'jpeg', 'png', 'webp')

# First bytes each extension must start with (contract "Uploads").
MAGIC_BYTES = {
    'pdf': (b'%PDF',),
    'jpg': (b'\xff\xd8\xff',),
    'jpeg': (b'\xff\xd8\xff',),
    'png': (b'\x89PNG\r\n\x1a\n',),
    # WebP is RIFF container: checked by `_is_webp` (two offsets), not a prefix.
    'webp': (),
    'docx': (b'PK\x03\x04',),
    'xlsx': (b'PK\x03\x04',),
    'doc': (b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1',),
    'xls': (b'\xd0\xcf\x11\xe0\xa1\xb1\x1a\xe1',),
    'dwg': (b'AC10',),
    # DXF is text, checked by `_is_dxf` instead of a fixed prefix.
    'dxf': (),
}

# MIME type used when the file is served. CAD files are octet-stream on purpose.
CONTENT_TYPES = {
    'pdf': 'application/pdf',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'png': 'image/png',
    'webp': 'image/webp',
    'doc': 'application/msword',
    'docx': (
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
    ),
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'dwg': 'application/octet-stream',
    'dxf': 'application/octet-stream',
}

HEAD_BYTES = 4096


def display_name(upload):
    """The sanitized original name, or a `400` for a traversal/invalid name.

    Refused rather than rewritten: a name like `../../x.pdf` is an attack, and
    silently renaming it would hide that from the caller.
    """
    raw = str(getattr(upload, 'name', '') or '')
    candidate = PurePosixPath(raw.replace('\\', '/')).name
    if (
        not candidate
        or candidate != raw.replace('\\', '/')
        or '..' in candidate
        or candidate.startswith('.')
    ):
        raise RuleRefused(rules.NAME_NOT_ALLOWED)
    return candidate


def extension_of(name):
    return PurePosixPath(name).suffix.lower().lstrip('.')


def _is_dxf(head):
    """A DXF is plain text and carries a SECTION marker."""
    if b'\x00' in head:
        return False
    try:
        text = head.decode('utf-8', errors='ignore')
    except UnicodeDecodeError:  # pragma: no cover - decode never raises with ignore
        return False
    return 'SECTION' in text.upper()


def _is_webp(head):
    """WebP is a RIFF container with `WEBP` at byte 8 (a bare RIFF is not enough)."""
    return len(head) >= 12 and head[:4] == b'RIFF' and head[8:12] == b'WEBP'


def _matches_magic(head, extension):
    if extension == 'dxf':
        return _is_dxf(head)
    if extension == 'webp':
        return _is_webp(head)
    return any(head.startswith(prefix) for prefix in MAGIC_BYTES[extension])


def check(upload, allowed, max_bytes):
    """Validate one upload and return `(display_name, extension)`.

    Raises `RuleRefused` (a `400 {"detail": ...}`) for a wrong extension, an
    extension/content mismatch, an oversize file, or a name we refuse.
    """
    name = display_name(upload)
    extension = extension_of(name)
    if extension not in allowed:
        raise RuleRefused(rules.document_type_refusal(allowed))

    size = int(getattr(upload, 'size', 0) or 0)
    if size <= 0:
        raise RuleRefused(rules.UPLOAD_FAILED)
    if size > max_bytes:
        raise RuleRefused(rules.size_refusal(max_bytes // (1024 * 1024)))

    upload.seek(0)
    head = upload.read(HEAD_BYTES)
    upload.seek(0)
    if not _matches_magic(head, extension):
        raise RuleRefused(rules.signature_refusal(extension))
    return name, extension


def check_document(upload):
    return check(upload, DOCUMENT_EXTENSIONS, settings.DOCUMENT_UPLOAD_MAX_BYTES)


def check_photo(upload):
    return check(upload, PHOTO_EXTENSIONS, settings.PHOTO_UPLOAD_MAX_BYTES)


def content_type(extension):
    return CONTENT_TYPES.get(extension, 'application/octet-stream')
