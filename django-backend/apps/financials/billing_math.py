"""Server-side billing maths, mirroring `progress_calculator.dart` and
`billing_calculator.dart`.

The desktop client computes a billing preview locally; the server must produce
the same figures, because the numbers stored on a billing are the invoice. Both
sides follow the same rules:

* progress is budget-weighted (equal shares when any category has no budget),
  counting only to-dos verified on or before the period end;
* `gross_earned = round2(progress × contract amount)`, cumulative;
* `this_period = gross_earned - the highest gross of an already-issued billing`;
* the down-payment recoupment and the retention are that period's percentage;
* `net_due = this_period - recoupment - retention`.

Rounding is half-up to 2 dp per line, like the mock's `_round`.
"""

from decimal import ROUND_HALF_UP, Decimal

from django.db.models import Max
from django.utils import timezone

from ..projects.models import Todo
from ..projects.serializers import category_weights
from .models import BillingStatus, ProgressBilling

CENT = Decimal('0.01')
PCT_QUANTUM = Decimal('0.000001')


def round2(value):
    """Half-up 2 dp, like Dart's `(v * 100).roundToDouble() / 100`."""
    return Decimal(value).quantize(CENT, rounding=ROUND_HALF_UP)


def project_progress(project, as_of):
    """Cumulative verified progress of `project` as of `as_of` (0–1)."""
    categories = list(project.categories.all())
    if not categories:
        return Decimal('0')

    weights = category_weights(project)
    todos = Todo.objects.filter(category__project=project).values_list(
        'category_id', 'is_verified', 'verified_at',
    )
    verified = {category.pk: 0 for category in categories}
    total = {category.pk: 0 for category in categories}
    for category_id, is_verified, verified_at in todos:
        total[category_id] += 1
        if is_verified and _verified_by(verified_at, as_of):
            verified[category_id] += 1

    progress = Decimal('0')
    for category in categories:
        if not total[category.pk]:
            continue
        share = Decimal(str(weights.get(category.pk, 0)))
        progress += share * (Decimal(verified[category.pk]) / Decimal(total[category.pk]))
    return min(progress, Decimal('1'))


def _verified_by(verified_at, as_of):
    """A verified to-do counts when it was verified on or before `as_of`."""
    if verified_at is None:
        return True
    return timezone.localtime(verified_at).date() <= as_of


def previous_gross(project):
    """The highest gross already issued (draft and withdrawn billings do not count)."""
    return ProgressBilling.objects.filter(project=project).exclude(
        status__in=(BillingStatus.DRAFT, BillingStatus.REJECTED),
    ).aggregate(total=Max('gross_earned'))['total'] or Decimal('0.00')


def previous_period_end(project):
    """The latest period end of a billing that was not withdrawn."""
    return ProgressBilling.objects.filter(project=project).exclude(
        status=BillingStatus.REJECTED,
    ).aggregate(latest=Max('period_end'))['latest']


def compute(project, progress, previous_gross_amount):
    """The figures one billing would show; nothing is stored."""
    gross = round2(progress * project.contract_amount)
    this_period = gross - previous_gross_amount
    recoupment = round2(this_period * project.down_payment_pct / Decimal('100'))
    retention = round2(this_period * project.retention_pct / Decimal('100'))
    return {
        'pct_accomplished': Decimal(progress).quantize(PCT_QUANTUM, rounding=ROUND_HALF_UP),
        'gross_earned': gross,
        'less_previous': round2(previous_gross_amount),
        'less_dp_recoupment': recoupment,
        'less_retention': retention,
        'this_period': round2(this_period),
        'net_due': round2(this_period - recoupment - retention),
    }


def preview(project, period_end):
    """`previewBilling`: progress as of `period_end`, less what was billed."""
    return compute(
        project,
        project_progress(project, period_end),
        previous_gross(project),
    )
