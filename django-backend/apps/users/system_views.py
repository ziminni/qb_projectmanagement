"""Admin-only system security, JWT session, and database backup endpoints."""

# Pyright here runs without django-stubs or DRF type stubs.
# pyright: reportGeneralTypeIssues=false, reportAttributeAccessIssue=false, reportArgumentType=false

import gzip
import hashlib
import io
import re
import uuid
from datetime import datetime, timezone as dt_timezone
from pathlib import Path

from django.conf import settings
from django.core.management import call_command
from django.db import connection, transaction
from django.http import FileResponse
from django.utils import timezone
from rest_framework import status
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.parsers import MultiPartParser
from rest_framework.response import Response
from rest_framework_simplejwt.token_blacklist.models import (
    BlacklistedToken,
    OutstandingToken,
)

from . import lockout, services
from .models import AuditLog, SystemBackupSchedule, SystemSecurityPolicy
from .permissions import IsAdmin

IsAdminRole = IsAdmin

_BACKUP_ID_RE = re.compile(r'^[A-Za-z0-9_.-]+$')
_BACKUP_EXT = '.json.gz'
_AUTH_EVENT_ACTIONS = (
    'login',
    'login_failed',
    'logout',
    'LOGIN',
    'LOGIN_FAILED',
    'LOGOUT',
)


def _backups_dir():
    return Path(settings.MEDIA_ROOT) / 'backups'


def _sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(65536), b''):
            digest.update(chunk)
    return digest.hexdigest()


def _policy_payload(policy: SystemSecurityPolicy) -> dict:
    return {
        'min_password_length': policy.min_password_length,
        'idle_timeout_minutes': policy.idle_timeout_minutes,
        'max_failed_logins': policy.max_failed_logins,
        'require_manager_override': policy.require_manager_override,
        'updated_at': policy.updated_at.isoformat() if policy.updated_at else None,
    }


def _schedule_payload(schedule: SystemBackupSchedule) -> dict:
    return {
        'frequency': schedule.frequency,
        'retention_count': schedule.retention_count,
        'last_backup_at': (
            schedule.last_backup_at.isoformat() if schedule.last_backup_at else None
        ),
        'updated_at': schedule.updated_at.isoformat() if schedule.updated_at else None,
    }


def _backup_payload(path: Path) -> dict:
    backup_id = path.name[:-len(_BACKUP_EXT)]
    stat = path.stat()
    created_at = datetime.fromtimestamp(stat.st_mtime, tz=dt_timezone.utc).isoformat()
    return {
        'id': backup_id,
        'filename': path.name,
        'size_bytes': stat.st_size,
        'sha256': _sha256_file(path),
        'created_at': created_at,
    }


def _resolve_backup_path(backup_id: str) -> Path | None:
    if not backup_id or not _BACKUP_ID_RE.match(backup_id) or '..' in backup_id:
        return None
    root = _backups_dir().resolve()
    candidate = (root / f'{backup_id}{_BACKUP_EXT}').resolve()
    if candidate.parent != root or not candidate.is_file():
        return None
    return candidate


def _enforce_retention(retention_count: int) -> None:
    root = _backups_dir()
    if not root.exists() or retention_count < 1:
        return
    files = sorted(
        root.glob(f'*{_BACKUP_EXT}'),
        key=lambda p: (p.stat().st_mtime, p.name),
        reverse=True,
    )
    for stale in files[retention_count:]:
        sidecar = stale.with_suffix('').with_suffix('.sha256')
        stale.unlink(missing_ok=True)
        sidecar.unlink(missing_ok=True)


def _parse_int(raw, field_name: str, minimum: int, maximum: int) -> tuple[int | None, str | None]:
    if isinstance(raw, bool):
        return None, f'{field_name} must be an integer.'
    try:
        value = int(raw)
    except (TypeError, ValueError):
        return None, f'{field_name} must be an integer.'
    if value < minimum or value > maximum:
        return None, f'{field_name} must be between {minimum} and {maximum}.'
    return value, None


# ---------------------------------------------------------------------------
# Security & Sessions
# ---------------------------------------------------------------------------

@api_view(['GET'])
@permission_classes([IsAdminRole])
def system_security_view(request):
    """Return live JWT sessions, recent auth audit events, and security policy."""
    now = timezone.now()
    blacklisted_ids = BlacklistedToken.objects.values_list('token_id', flat=True)
    tokens = (
        OutstandingToken.objects.select_related('user')
        .filter(expires_at__gt=now)
        .exclude(id__in=blacklisted_ids)
        .order_by('-created_at', '-id')
    )
    sessions = [
        {
            'id': tok.pk,
            'user_id': tok.user_id,
            'user_email': tok.user.email if tok.user else '',
            'user_name': tok.user.full_name if tok.user else '',
            'jti': tok.jti,
            'created_at': tok.created_at.isoformat() if tok.created_at else None,
            'expires_at': tok.expires_at.isoformat() if tok.expires_at else None,
        }
        for tok in tokens
    ]

    events_qs = (
        AuditLog.objects.select_related('user')
        .filter(action__in=_AUTH_EVENT_ACTIONS)
        .order_by('-created_at', '-id')[:50]
    )
    events = [
        {
            'id': row.pk,
            'user_id': row.user_id,
            'user_email': row.user.email,
            'user_name': row.user.full_name,
            'action': row.action,
            'details': row.details,
            'created_at': row.created_at.isoformat(),
        }
        for row in events_qs
    ]

    policy = SystemSecurityPolicy.objects.first() or SystemSecurityPolicy()
    return Response({
        'sessions': sessions,
        'events': events,
        'policy': _policy_payload(policy),
    })


@api_view(['POST'])
@permission_classes([IsAdminRole])
def system_session_revoke_view(request, pk: int):
    """Blacklist an outstanding JWT refresh token and record a logout audit row."""
    token = OutstandingToken.objects.select_related('user').filter(pk=pk).first()
    if token is None:
        return Response({'detail': 'Session not found.'}, status=status.HTTP_404_NOT_FOUND)

    with transaction.atomic():
        BlacklistedToken.objects.get_or_create(token=token)
        services.record(
            request.user,
            'logout',
            'session',
            token.pk,
            {
                'target_user_id': token.user_id,
                'target_email': token.user.email if token.user else '',
                'revoked_by_admin': True,
            },
        )
    return Response({'detail': 'Session revoked.', 'id': token.pk})


@api_view(['POST'])
@permission_classes([IsAdminRole])
def system_sessions_revoke_all_view(request):
    """Blacklist all active refresh tokens (optionally scoped to one user)."""
    data = request.data if isinstance(request.data, dict) else {}
    target_user_id = data.get('user_id')
    now = timezone.now()
    blacklisted_ids = BlacklistedToken.objects.values_list('token_id', flat=True)
    qs = (
        OutstandingToken.objects.filter(expires_at__gt=now)
        .exclude(id__in=blacklisted_ids)
    )
    if target_user_id is not None:
        qs = qs.filter(user_id=target_user_id)
    else:
        qs = qs.exclude(user=request.user)

    tokens = list(qs)
    with transaction.atomic():
        for tok in tokens:
            BlacklistedToken.objects.get_or_create(token=tok)
        services.record(
            request.user,
            'logout',
            'session',
            int(target_user_id) if target_user_id is not None else 0,
            {'revoked_count': len(tokens), 'revoked_by_admin': True},
        )
    return Response({'detail': f'Revoked {len(tokens)} session(s).', 'count': len(tokens)})


@api_view(['PATCH'])
@permission_classes([IsAdminRole])
def system_security_policy_view(request):
    """Update persisted security policy and live lockout threshold."""
    data = request.data if isinstance(request.data, dict) else {}
    policy, _ = SystemSecurityPolicy.objects.get_or_create(pk=1)

    if 'min_password_length' in data:
        val, err = _parse_int(data['min_password_length'], 'min_password_length', 6, 128)
        if err:
            return Response({'detail': err}, status=status.HTTP_400_BAD_REQUEST)
        policy.min_password_length = val

    if 'idle_timeout_minutes' in data:
        val, err = _parse_int(data['idle_timeout_minutes'], 'idle_timeout_minutes', 5, 1440)
        if err:
            return Response({'detail': err}, status=status.HTTP_400_BAD_REQUEST)
        policy.idle_timeout_minutes = val

    if 'max_failed_logins' in data:
        val, err = _parse_int(data['max_failed_logins'], 'max_failed_logins', 1, 20)
        if err:
            return Response({'detail': err}, status=status.HTTP_400_BAD_REQUEST)
        policy.max_failed_logins = val

    if 'require_manager_override' in data:
        if not isinstance(data['require_manager_override'], bool):
            return Response(
                {'detail': 'require_manager_override must be a boolean.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        policy.require_manager_override = data['require_manager_override']

    with transaction.atomic():
        policy.save()
        lockout.MAX_FAILURES = policy.max_failed_logins
        services.record(
            request.user,
            'settings_updated',
            'security_policy',
            policy.pk,
            {
                'min_password_length': policy.min_password_length,
                'idle_timeout_minutes': policy.idle_timeout_minutes,
                'max_failed_logins': policy.max_failed_logins,
                'require_manager_override': policy.require_manager_override,
            },
        )
    return Response(_policy_payload(policy))


# ---------------------------------------------------------------------------
# Database Backup & Restore
# ---------------------------------------------------------------------------

@api_view(['GET', 'POST'])
@permission_classes([IsAdminRole])
def system_backups_view(request):
    """List server snapshots + schedule (GET) or create a new dump (POST)."""
    if request.method == 'GET':
        root = _backups_dir()
        files = []
        if root.exists():
            files = sorted(
                root.glob(f'*{_BACKUP_EXT}'),
                key=lambda p: (p.stat().st_mtime, p.name),
                reverse=True,
            )
        schedule = SystemBackupSchedule.objects.first() or SystemBackupSchedule()
        return Response({
            'backups': [_backup_payload(p) for p in files],
            'schedule': _schedule_payload(schedule),
        })

    root = _backups_dir()
    root.mkdir(parents=True, exist_ok=True)
    stamp = timezone.now().strftime('%Y%m%d_%H%M%S')
    backup_id = f'cpms_backup_{stamp}_{uuid.uuid4().hex[:6]}'
    archive_path = root / f'{backup_id}{_BACKUP_EXT}'
    sidecar_path = root / f'{backup_id}.sha256'

    buf = io.StringIO()
    call_command(
        'dumpdata',
        exclude=['contenttypes', 'auth.permission'],
        natural_foreign=True,
        natural_primary=True,
        stdout=buf,
    )
    with gzip.open(archive_path, 'wt', encoding='utf-8') as gz:
        gz.write(buf.getvalue())

    digest = _sha256_file(archive_path)
    sidecar_path.write_text(digest, encoding='utf-8')

    with transaction.atomic():
        schedule, _ = SystemBackupSchedule.objects.get_or_create(pk=1)
        schedule.last_backup_at = timezone.now()
        schedule.save()
        _enforce_retention(schedule.retention_count)
        services.record(
            request.user,
            'backup_created',
            'backup',
            0,
            {
                'backup_id': backup_id,
                'size_bytes': archive_path.stat().st_size,
                'sha256': digest,
            },
        )

    return Response(_backup_payload(archive_path), status=status.HTTP_201_CREATED)


@api_view(['GET'])
@permission_classes([IsAdminRole])
def system_backup_download_view(request, backup_id: str):
    """Stream a server backup archive for download."""
    path = _resolve_backup_path(backup_id)
    if path is None:
        return Response({'detail': 'Backup not found.'}, status=status.HTTP_404_NOT_FOUND)
    return FileResponse(
        path.open('rb'),
        as_attachment=True,
        filename=path.name,
        content_type='application/gzip',
    )


@api_view(['POST'])
@permission_classes([IsAdminRole])
def system_backup_restore_view(request):
    """Verify SHA-256 checksum and restore database records from a snapshot."""
    data = request.data if isinstance(request.data, dict) else {}
    backup_id = str(data.get('id') or data.get('backup_id') or '').strip()
    path = _resolve_backup_path(backup_id)
    if path is None:
        return Response({'detail': 'Backup not found.'}, status=status.HTTP_404_NOT_FOUND)

    actual_sha256 = _sha256_file(path)
    sidecar = _backups_dir() / f'{backup_id}.sha256'
    expected_sha256 = (
        sidecar.read_text(encoding='utf-8').strip()
        if sidecar.is_file()
        else str(data.get('sha256') or '').strip()
    )
    if expected_sha256 and actual_sha256 != expected_sha256:
        return Response(
            {'detail': 'Backup checksum verification failed.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    with transaction.atomic():
        call_command('loaddata', str(path), verbosity=0)
        services.record(
            request.user,
            'backup_restored',
            'backup',
            0,
            {'backup_id': backup_id, 'sha256': actual_sha256},
        )
    return Response({'detail': 'Backup restored.', 'id': backup_id})


@api_view(['PATCH'])
@permission_classes([IsAdminRole])
def system_backup_schedule_view(request):
    """Update automated backup frequency and retention count."""
    data = request.data if isinstance(request.data, dict) else {}
    schedule, _ = SystemBackupSchedule.objects.get_or_create(pk=1)

    if 'frequency' in data:
        freq = str(data['frequency']).strip()
        valid = {choice for choice, _ in SystemBackupSchedule.Frequency.choices}
        if freq not in valid:
            return Response(
                {'detail': f'frequency must be one of: {", ".join(sorted(valid))}.'},
                status=status.HTTP_400_BAD_REQUEST,
            )
        schedule.frequency = freq

    if 'retention_count' in data:
        val, err = _parse_int(data['retention_count'], 'retention_count', 1, 90)
        if err:
            return Response({'detail': err}, status=status.HTTP_400_BAD_REQUEST)
        schedule.retention_count = val

    with transaction.atomic():
        schedule.save()
        _enforce_retention(schedule.retention_count)
        services.record(
            request.user,
            'settings_updated',
            'backup_schedule',
            schedule.pk,
            {
                'frequency': schedule.frequency,
                'retention_count': schedule.retention_count,
            },
        )
    return Response(_schedule_payload(schedule))


@api_view(['POST'])
@permission_classes([IsAdminRole])
@parser_classes([MultiPartParser])
def system_backup_upload_restore_view(request):
    """Upload a .json.gz or .json backup archive, save it, and restore it."""
    upload = request.FILES.get('file')
    if upload is None:
        return Response(
            {'detail': 'Attach a backup file (.json.gz or .json).'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    if upload.size > 50 * 1024 * 1024:
        return Response(
            {'detail': 'Backup file must be 50 MB or smaller.'},
            status=status.HTTP_400_BAD_REQUEST,
        )
    raw_name = Path(upload.name or '').name
    if not (raw_name.endswith('.json.gz') or raw_name.endswith('.json')):
        return Response(
            {'detail': 'Only .json.gz or .json backup archives are supported.'},
            status=status.HTTP_400_BAD_REQUEST,
        )

    root = _backups_dir()
    root.mkdir(parents=True, exist_ok=True)
    stamp = timezone.now().strftime('%Y%m%d_%H%M%S')
    backup_id = f'cpms_upload_{stamp}_{uuid.uuid4().hex[:6]}'
    ext = '.json.gz' if raw_name.endswith('.json.gz') else '.json'
    target = root / f'{backup_id}{ext}'
    with target.open('wb') as out:
        for chunk in upload.chunks():
            out.write(chunk)

    digest = _sha256_file(target)
    if ext == '.json.gz':
        (root / f'{backup_id}.sha256').write_text(digest, encoding='utf-8')

    with transaction.atomic():
        call_command('loaddata', str(target), verbosity=0)
        services.record(
            request.user,
            'backup_restored',
            'backup',
            0,
            {'backup_id': backup_id, 'sha256': digest, 'uploaded': True},
        )
    return Response({'detail': 'Uploaded backup restored.', 'id': backup_id})


def _dir_size(path: Path) -> int:
    if not path.exists():
        return 0
    return sum(p.stat().st_size for p in path.rglob('*') if p.is_file())


@api_view(['GET'])
@permission_classes([IsAdminRole])
def system_health_view(request):
    """Return database health, private_media storage usage, and POS outbox status."""
    from apps.requisitions.models import PosOutboxJob, PosOutboxState

    db_ok = True
    try:
        connection.ensure_connection()
    except Exception:
        db_ok = False

    media_root = Path(settings.MEDIA_ROOT)
    backups_bytes = _dir_size(media_root / 'backups')
    reports_bytes = _dir_size(media_root / 'reports')
    documents_bytes = _dir_size(media_root / 'documents')
    total_bytes = _dir_size(media_root)

    pending_count = PosOutboxJob.objects.filter(
        state=PosOutboxState.PENDING,
    ).count()
    failed_count = PosOutboxJob.objects.filter(
        state=PosOutboxState.FAILED,
    ).count()
    synced_count = PosOutboxJob.objects.filter(
        state=PosOutboxState.DONE,
    ).count()

    jobs_qs = (
        PosOutboxJob.objects.select_related('purchase_order', 'purchase_order__project')
        .exclude(state__in=[PosOutboxState.DONE, PosOutboxState.CANCELLED])
        .order_by('-updated_at', '-id')[:20]
    )
    jobs = [
        {
            'id': j.pk,
            'purchase_order_id': j.purchase_order_id,
            'po_number': j.purchase_order.po_number,
            'project_name': j.purchase_order.project.name,
            'operation': j.operation,
            'state': j.state,
            'attempts': j.attempts,
            'last_error': j.last_error,
            'updated_at': j.updated_at.isoformat(),
        }
        for j in jobs_qs
    ]

    pos_reachable = None
    probe_error = None
    if request.query_params.get('probe_pos') == '1':
        try:
            import requests

            base = getattr(settings, 'POS_API_BASE_URL', '').rstrip('/')
            if not base:
                pos_reachable = False
                probe_error = 'POS_API_BASE_URL is not configured.'
            else:
                r = requests.get(f'{base}/api/health/', timeout=3)
                pos_reachable = r.status_code < 500
                if not pos_reachable:
                    probe_error = f'HTTP {r.status_code}'
        except Exception as exc:
            pos_reachable = False
            probe_error = str(exc)

    return Response({
        'database': 'ok' if db_ok else 'error',
        'storage': {
            'backups_bytes': backups_bytes,
            'reports_bytes': reports_bytes,
            'documents_bytes': documents_bytes,
            'total_bytes': total_bytes,
        },
        'pos_bridge': {
            'base_url': getattr(settings, 'POS_API_BASE_URL', ''),
            'pending_count': pending_count,
            'failed_count': failed_count,
            'synced_count': synced_count,
            'pos_reachable': pos_reachable,
            'probe_error': probe_error,
            'jobs': jobs,
        },
    })


@api_view(['POST'])
@permission_classes([IsAdminRole])
def system_pos_retry_view(request, job_id: int):
    """Re-queue a failed or needs-review POS outbox job."""
    from apps.requisitions.models import PosOutboxJob, PosOutboxState

    job = PosOutboxJob.objects.select_related('purchase_order').filter(pk=job_id).first()
    if job is None:
        return Response({'detail': 'Outbox job not found.'}, status=status.HTTP_404_NOT_FOUND)

    with transaction.atomic():
        job.state = PosOutboxState.PENDING
        job.attempts = 0
        job.next_attempt_at = timezone.now()
        job.last_error = ''
        job.save(update_fields=['state', 'attempts', 'next_attempt_at', 'last_error', 'updated_at'])
        services.record(
            request.user,
            'pos_sync_retried',
            'pos_outbox_job',
            job.pk,
            {'po_number': job.purchase_order.po_number},
        )
    return Response({'detail': 'Sync job re-queued.', 'id': job.pk})
