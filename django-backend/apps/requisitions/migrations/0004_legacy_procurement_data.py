"""Copy the provable pre-Phase-3 requisition values forward (nothing is deleted).

Same rule as Phase 2's `0005_legacy_project_data`: the legacy row and every
legacy column stay; only values that mean exactly the same thing in the Phase 3
shape are folded. Everything ambiguous stays where it is and the raw code is
kept verbatim in `legacy_status`.

What is folded (source -> destination):

| Legacy `MaterialRequest.status` | `status`  | Why |
| --- | --- | --- |
| `DRAFT`, `PENDING`              | `pending` | nobody has ordered it yet |
| `APPROVED`, `PARTIALLY_APPROVED` | `pending` | approval was not an order; no PO row exists, and `ordered` would claim one does |
| `REJECTED`, `CANCELLED`         | `rejected` | refused; the raw code says which |
| `RELEASED`                      | `ordered` | material provably left the store, so an order existed |

`needed_date` -> `needed_by` (the same fact, new column name; `needed_date` is
kept). `reviewed_by` -> `approved_by` **only** for rows that map to `ordered`,
because in the Phase 3 shape `approved_by` is "the owner who answered this
request with an order". A review of a request that was never ordered is not
that.

Not folded: `quantity_approved` / `quantity_released` / `unit_cost` /
`item_sku` (no Phase 3 column means the same thing), and `ReleaseToken` rows
(the legacy token workflow is retired, the history stays).
"""

from django.db import migrations

# Legacy code -> Phase 3 status.
STATUS_MAP = {
    'DRAFT': 'pending',
    'PENDING': 'pending',
    'APPROVED': 'pending',
    'PARTIALLY_APPROVED': 'pending',
    'REJECTED': 'rejected',
    'CANCELLED': 'rejected',
    'RELEASED': 'ordered',
}


def forwards(apps, schema_editor):
    MaterialRequest = apps.get_model('apps_requisitions', 'MaterialRequest')
    for row in MaterialRequest.objects.all().only(
        'pk', 'status', 'needed_date', 'needed_by', 'reviewed_by',
        'approved_by', 'legacy_status',
    ):
        raw_status = row.status
        mapped = STATUS_MAP.get(raw_status)
        if mapped is None:
            # Unknown code: leave the row parseable, keep the raw value.
            mapped = 'pending'
        row.legacy_status = raw_status
        row.status = mapped
        if row.needed_by is None and row.needed_date is not None:
            row.needed_by = row.needed_date
        if mapped == 'ordered' and row.approved_by_id is None:
            row.approved_by_id = row.reviewed_by_id
        row.save(
            update_fields=[
                'legacy_status', 'status', 'needed_by', 'approved_by',
            ]
        )


def backwards(apps, schema_editor):
    MaterialRequest = apps.get_model('apps_requisitions', 'MaterialRequest')
    for row in MaterialRequest.objects.exclude(legacy_status='').only(
        'pk', 'status', 'legacy_status',
    ):
        row.status = row.legacy_status
        row.save(update_fields=['status'])


class Migration(migrations.Migration):

    dependencies = [
        ('apps_requisitions', '0003_procurement_phase3'),
    ]

    operations = [
        migrations.RunPython(forwards, backwards),
    ]
