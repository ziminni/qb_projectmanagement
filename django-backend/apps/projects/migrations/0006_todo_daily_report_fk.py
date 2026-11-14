"""Turn `Todo.daily_report_id` (a bare integer) into a real nullable FK.

Phase 2.1 shipped the column without a table to point at. 2.2 creates
`apps_site_reports.DailyReport`, so the column can become the FK Flutter expects
(`models/todo.dart`).

No value is dropped: a legacy id that matches an existing report keeps its link,
and one that matches nothing is moved to `legacy_daily_report_id` (kept, not
exposed) before the FK constraint is added. A fresh `makemigrations` would have
dropped the column instead, which is why this migration is hand-written.

Reverse: the FK is widened back to a bigint and the moved values return.
"""

from django.db import migrations, models
from django.db.models import F


def preserve_unmatched_links(apps, schema_editor):
    """Move ids that match no report aside, so the FK stays satisfiable."""
    Todo = apps.get_model('apps_projects', 'Todo')
    DailyReport = apps.get_model('apps_site_reports', 'DailyReport')
    known = set(DailyReport.objects.values_list('pk', flat=True))
    orphans = Todo.objects.filter(daily_report_id__isnull=False).exclude(
        daily_report_id__in=known,
    )
    count = orphans.count()
    if count:
        orphans.update(
            legacy_daily_report_id=F('daily_report_id'),
            daily_report_id=None,
        )
        print(
            f'  {count} to-do report link(s) matched no report; '
            'kept in legacy_daily_report_id.'
        )


def restore_unmatched_links(apps, schema_editor):
    """Reverse: put the preserved ids back into the integer column."""
    Todo = apps.get_model('apps_projects', 'Todo')
    Todo.objects.filter(
        daily_report_id__isnull=True, legacy_daily_report_id__isnull=False,
    ).update(daily_report_id=F('legacy_daily_report_id'))


class Migration(migrations.Migration):

    dependencies = [
        ('apps_projects', '0005_legacy_project_data'),
        ('apps_site_reports', '0001_initial'),
    ]

    operations = [
        migrations.AddField(
            model_name='todo',
            name='legacy_daily_report_id',
            field=models.BigIntegerField(
                blank=True,
                help_text='Pre-2.2 report id that matched no report; kept, not exposed.',
                null=True,
            ),
        ),
        migrations.RunPython(preserve_unmatched_links, restore_unmatched_links),
        migrations.RenameField(
            model_name='todo',
            old_name='daily_report_id',
            new_name='daily_report',
        ),
        migrations.AlterField(
            model_name='todo',
            name='daily_report',
            field=models.ForeignKey(
                blank=True,
                null=True,
                on_delete=models.deletion.SET_NULL,
                related_name='todos',
                to='apps_site_reports.dailyreport',
            ),
        ),
    ]
