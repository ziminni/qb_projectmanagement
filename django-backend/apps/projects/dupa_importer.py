"""Zero-dependency DPWH DUPA (.xlsx) workbook parser.

Reads standard Philippine DPWH Detailed Unit Price Analysis (DUPA) Excel files
where each worksheet represents one Item of Work (e.g. `B.7(2)` — Occupational
Safety & Health Program) with:
  - `Item No.` + Description
  - Section A (Labor) → `Sub Total A`
  - Section B (Equipment) → `Sub Total B`
  - Section C (Materials: Name & Specification, Unit, Qty, Unit Cost, Amount) → `Sub total C`
  - `D` Estimated Direct Cost, `I` Total Adjusted Cost
"""

from datetime import timedelta
from decimal import Decimal, InvalidOperation
import csv
import io
import re
import xml.etree.ElementTree as ET
import zipfile

NS_MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
NS_REL = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
NS_PKG_REL = 'http://schemas.openxmlformats.org/package/2006/relationships'

_COL_RE = re.compile(r'^([A-Za-z]+)')


def _col_index(cell_ref):
    match = _COL_RE.match(cell_ref or '')
    if not match:
        return 0
    idx = 0
    for ch in match.group(1).upper():
        idx = idx * 26 + (ord(ch) - ord('A') + 1)
    return idx - 1


def _to_decimal(val):
    if val is None:
        return None
    s = str(val).strip().replace(',', '').replace('₱', '').replace('PHP', '').strip()
    if not s or s == '-':
        return None
    try:
        d = Decimal(s)
        if not d.is_finite():
            return None
        return d.quantize(Decimal('0.01'))
    except InvalidOperation:
        return None


def _read_shared_strings(zf):
    if 'xl/sharedStrings.xml' not in zf.namelist():
        return []
    root = ET.fromstring(zf.read('xl/sharedStrings.xml'))
    strings = []
    for si in root.findall(f'{{{NS_MAIN}}}si'):
        parts = [t.text or '' for t in si.iter(f'{{{NS_MAIN}}}t')]
        strings.append(''.join(parts))
    return strings


def _read_workbook_sheets(zf):
    """Return list of ``(sheet_name, zip_entry_path)`` in workbook order."""
    wb_root = ET.fromstring(zf.read('xl/workbook.xml'))
    rel_map = {}
    if 'xl/_rels/workbook.xml.rels' in zf.namelist():
        rel_root = ET.fromstring(zf.read('xl/_rels/workbook.xml.rels'))
        for rel in rel_root.findall(f'{{{NS_PKG_REL}}}Relationship'):
            rel_map[rel.attrib.get('Id', '')] = rel.attrib.get('Target', '')

    sheets = []
    for sheet in wb_root.findall(f'.//{{{NS_MAIN}}}sheet'):
        name = sheet.attrib.get('name', 'Sheet')
        rid = sheet.attrib.get(f'{{{NS_REL}}}id', '')
        target = rel_map.get(rid, '')
        if not target:
            continue
        target = target.lstrip('/')
        if not target.startswith('xl/'):
            target = f'xl/{target}'
        if target in zf.namelist():
            sheets.append((name, target))
    return sheets


def _read_sheet_grid(zf, entry_path, shared_strings):
    """Return list of rows, each row a dict ``{col_index: str}``."""
    root = ET.fromstring(zf.read(entry_path))
    rows = []
    for row_el in root.findall(f'.//{{{NS_MAIN}}}sheetData/{{{NS_MAIN}}}row'):
        row = {}
        for cell in row_el.findall(f'{{{NS_MAIN}}}c'):
            col = _col_index(cell.attrib.get('r', ''))
            ctype = cell.attrib.get('t', '')
            if ctype == 's':
                v = cell.find(f'{{{NS_MAIN}}}v')
                if v is not None and v.text is not None:
                    idx = int(v.text)
                    val = shared_strings[idx] if 0 <= idx < len(shared_strings) else ''
                else:
                    val = ''
            elif ctype == 'inlineStr':
                parts = [t.text or '' for t in cell.iter(f'{{{NS_MAIN}}}t')]
                val = ''.join(parts)
            else:
                v = cell.find(f'{{{NS_MAIN}}}v')
                val = (v.text or '') if v is not None else ''
            val = str(val).strip()
            if val:
                row[col] = val
        if row:
            rows.append(row)
    return rows


def _row_texts(row):
    return [(col, row[col]) for col in sorted(row)]


def _rightmost_decimal(row):
    for col in sorted(row.keys(), reverse=True):
        d = _to_decimal(row[col])
        if d is not None:
            return d
    return None


def _extract_pct_label(row):
    for _, text in _row_texts(row):
        if '%' in text:
            return text.strip()
    return ''


def _parse_dupa_sheet(sheet_name, rows):
    item_no = ''
    description = ''
    unit_of_measurement = ''
    labor_budget = None
    equipment_budget = None
    material_budget = None
    direct_cost = None
    unit_cost = None
    ocm_pct = ''
    ocm_amount = None
    profit_pct = ''
    profit_amount = None
    vat_pct = ''
    vat_amount = None
    adjusted_cost = None
    adjusted_unit_cost = None

    section = None  # 'A', 'B', 'C', or None
    a_name_col = a_persons_col = a_hours_col = a_rate_col = a_amt_col = None
    b_name_col = b_units_col = b_hours_col = b_rate_col = b_amt_col = None
    mat_name_col = mat_unit_col = mat_qty_col = mat_cost_col = None

    labor_rows = []
    equipment_rows = []
    materials = []

    for row in rows:
        ordered = _row_texts(row)
        joined_lower = ' '.join(t.lower() for _, t in ordered)

        # Header: Item No. | B.7(2) | Occupational Safety & Health Program
        if not item_no and any(
            t.lower().replace(' ', '') in ('itemno.', 'itemno', 'itemno.:', 'payitemno.')
            for _, t in ordered
        ):
            non_label = [
                t for _, t in ordered
                if t.lower().replace(' ', '') not in ('itemno.', 'itemno', 'itemno.:', 'payitemno.')
            ]
            if non_label:
                item_no = non_label[0].strip()
            if len(non_label) >= 2:
                description = ' '.join(non_label[1:]).strip()
            continue

        # Unit of Measurement row
        if not unit_of_measurement and 'unit of measurement' in joined_lower:
            non_label = [
                t.strip() for _, t in ordered
                if 'unit of measurement' not in t.lower()
            ]
            if non_label:
                unit_of_measurement = ' '.join(non_label)[:64]
            continue

        # Detect Section A header row (Designation | No. Of Person | No. Of Hrs | Rate per Hr | Amount)
        if 'designation' in joined_lower and ('person' in joined_lower or 'hrs' in joined_lower or 'rate' in joined_lower):
            section = 'A'
            for col, text in ordered:
                tl = text.lower()
                if 'designation' in tl:
                    a_name_col = col
                elif 'person' in tl:
                    a_persons_col = col
                elif 'hr' in tl and 'rate' not in tl:
                    a_hours_col = col
                elif 'rate' in tl:
                    a_rate_col = col
                elif 'amount' in tl:
                    a_amt_col = col
            continue

        # Detect Section B header row (Name & Capacity | No. Of Units | No. Of Hrs | Rate per Hr | Amount)
        if ('capacity' in joined_lower or 'no. of units' in joined_lower or 'no of units' in joined_lower) and (
            'hrs' in joined_lower or 'rate' in joined_lower or 'amount' in joined_lower
        ):
            section = 'B'
            for col, text in ordered:
                tl = text.lower()
                if 'name' in tl or 'capacity' in tl or 'equipment' in tl:
                    b_name_col = col
                elif 'unit' in tl:
                    b_units_col = col
                elif 'hr' in tl and 'rate' not in tl:
                    b_hours_col = col
                elif 'rate' in tl:
                    b_rate_col = col
                elif 'amount' in tl:
                    b_amt_col = col
            continue

        # Detect Section C header row (Name & Specification | Unit | Qty | Unit Cost | Amount)
        if 'name' in joined_lower and 'unit' in joined_lower and 'qty' in joined_lower:
            section = 'C'
            for col, text in ordered:
                tl = text.lower()
                if 'name' in tl or 'specification' in tl or 'material' in tl:
                    mat_name_col = col
                elif tl in ('unit', 'u/m', 'uom'):
                    mat_unit_col = col
                elif 'qty' in tl or 'quantity' in tl:
                    mat_qty_col = col
                elif 'unit cost' in tl or 'rate' in tl:
                    mat_cost_col = col
            continue

        # Subtotals & summary rows (D through J)
        if 'sub total a' in joined_lower or 'subtotal a' in joined_lower:
            labor_budget = _rightmost_decimal(row)
            section = None
            continue
        if 'sub total b' in joined_lower or 'subtotal b' in joined_lower:
            equipment_budget = _rightmost_decimal(row)
            section = None
            continue
        if 'sub total c' in joined_lower or 'subtotal c' in joined_lower:
            material_budget = _rightmost_decimal(row)
            section = None
            continue
        if 'estimated direct cost' in joined_lower:
            direct_cost = _rightmost_decimal(row)
            section = None
            continue
        if 'adjusted unit cost' in joined_lower:
            adjusted_unit_cost = _rightmost_decimal(row)
            section = None
            continue
        if 'total adjusted cost' in joined_lower:
            adjusted_cost = _rightmost_decimal(row)
            section = None
            continue
        if 'unit cost' in joined_lower and section is None and unit_cost is None and direct_cost is not None:
            unit_cost = _rightmost_decimal(row)
            continue
        if 'ocm' in joined_lower and section is None and ocm_amount is None:
            ocm_pct = _extract_pct_label(row)
            ocm_amount = _rightmost_decimal(row)
            continue
        if ("contractor's profit" in joined_lower or 'contractors profit' in joined_lower or 'profit (cp)' in joined_lower) and section is None:
            profit_pct = _extract_pct_label(row)
            profit_amount = _rightmost_decimal(row)
            continue
        if ('vat' in joined_lower.split() or 'v.a.t.' in joined_lower or 'vat ' in joined_lower) and section is None and vat_amount is None:
            vat_pct = _extract_pct_label(row)
            vat_amount = _rightmost_decimal(row)
            continue

        # Section A labor rows
        if section == 'A':
            if all(t.lower() in ('a', 'labor', 'labour') for _, t in ordered):
                continue
            name_val = (row.get(a_name_col, '') if a_name_col is not None else '').strip()
            if not name_val:
                for col, text in ordered:
                    if a_persons_col is not None and col >= a_persons_col:
                        break
                    if text.lower() in ('a', 'labor', 'labour'):
                        continue
                    if _to_decimal(text) is None:
                        name_val = text
                        break
            if not name_val:
                continue
            persons = _to_decimal(row.get(a_persons_col)) if a_persons_col is not None else None
            hours = _to_decimal(row.get(a_hours_col)) if a_hours_col is not None else None
            rate = _to_decimal(row.get(a_rate_col)) if a_rate_col is not None else None
            amt = _to_decimal(row.get(a_amt_col)) if a_amt_col is not None else _rightmost_decimal(row)
            if (amt is None or amt <= 0) and (persons is None or persons <= 0):
                continue
            labor_rows.append({
                'designation': name_val[:255],
                'persons': str(persons) if persons is not None else '0.00',
                'hours': str(hours) if hours is not None else '0.00',
                'rate': str(rate) if rate is not None else '0.00',
                'amount': str(amt) if amt is not None else '0.00',
            })
            continue

        # Section B equipment rows
        if section == 'B':
            if all(t.lower() in ('b', 'equipment') for _, t in ordered):
                continue
            name_val = (row.get(b_name_col, '') if b_name_col is not None else '').strip()
            if not name_val:
                for col, text in ordered:
                    if b_units_col is not None and col >= b_units_col:
                        break
                    if text.lower() in ('b', 'equipment'):
                        continue
                    if _to_decimal(text) is None:
                        name_val = text
                        break
            if not name_val:
                continue
            units = _to_decimal(row.get(b_units_col)) if b_units_col is not None else None
            hours = _to_decimal(row.get(b_hours_col)) if b_hours_col is not None else None
            rate = _to_decimal(row.get(b_rate_col)) if b_rate_col is not None else None
            amt = _to_decimal(row.get(b_amt_col)) if b_amt_col is not None else _rightmost_decimal(row)
            if (amt is None or amt <= 0) and (units is None or units <= 0):
                continue
            equipment_rows.append({
                'name': name_val[:255],
                'units': str(units) if units is not None else '0.00',
                'hours': str(hours) if hours is not None else '0.00',
                'rate': str(rate) if rate is not None else '0.00',
                'amount': str(amt) if amt is not None else '0.00',
            })
            continue

        # Section C material rows
        if section == 'C':
            if len(ordered) == 1 and ordered[0][1].lower() in ('c', 'materials', 'material'):
                continue
            name_val = row.get(mat_name_col, '').strip() if mat_name_col is not None else ''
            if not name_val:
                for col, text in ordered:
                    if mat_unit_col is not None and col >= mat_unit_col:
                        break
                    if text.lower() in ('c', 'materials', 'material'):
                        continue
                    if _to_decimal(text) is None:
                        name_val = text
                        break
            if not name_val:
                continue
            unit_val = (row.get(mat_unit_col, '') if mat_unit_col is not None else '').strip() or 'pcs'
            qty_val = _to_decimal(row.get(mat_qty_col)) if mat_qty_col is not None else None
            cost_val = _to_decimal(row.get(mat_cost_col)) if mat_cost_col is not None else None
            if qty_val is None or qty_val <= 0:
                continue
            materials.append({
                'name': name_val[:255],
                'unit': unit_val[:32],
                'planned_qty': qty_val,
                'unit_cost': cost_val if cost_val is not None and cost_val >= 0 else Decimal('0.00'),
            })

    # Must look like an actual DUPA sheet (has item_no/description or materials/costs)
    if not item_no and not description and not materials and not labor_rows and not equipment_rows:
        return None
    if not description and not materials and not labor_rows and adjusted_cost is None and direct_cost is None:
        return None

    display_name = (
        f'{item_no} — {description}'
        if item_no and description and not description.lower().startswith(item_no.lower())
        else (description or item_no or sheet_name)
    )
    budget = adjusted_cost if adjusted_cost is not None else direct_cost
    if budget is None and any(x is not None for x in (labor_budget, equipment_budget, material_budget)):
        budget = (labor_budget or Decimal('0.00')) + (equipment_budget or Decimal('0.00')) + (material_budget or Decimal('0.00'))

    def _dec_str(val):
        return str(val) if val is not None else None

    dupa_breakdown = {
        'sheet': sheet_name,
        'item_no': item_no[:32],
        'description': (description or display_name)[:255],
        'unit_of_measurement': unit_of_measurement,
        'labor': labor_rows,
        'equipment': equipment_rows,
        'materials': [
            {
                'name': m['name'],
                'unit': m['unit'],
                'qty': str(m['planned_qty']),
                'unit_cost': str(m['unit_cost']),
                'amount': str((m['planned_qty'] * m['unit_cost']).quantize(Decimal('0.01'))),
            }
            for m in materials
        ],
        'sub_total_a': _dec_str(labor_budget),
        'sub_total_b': _dec_str(equipment_budget),
        'sub_total_c': _dec_str(material_budget),
        'direct_cost': _dec_str(direct_cost),
        'unit_cost': _dec_str(unit_cost),
        'ocm_pct': ocm_pct,
        'ocm_amount': _dec_str(ocm_amount),
        'profit_pct': profit_pct,
        'profit_amount': _dec_str(profit_amount),
        'vat_pct': vat_pct,
        'vat_amount': _dec_str(vat_amount),
        'total_adjusted_cost': _dec_str(adjusted_cost or budget),
        'adjusted_unit_cost': _dec_str(adjusted_unit_cost),
    }

    return {
        'sheet': sheet_name,
        'item_no': item_no[:32],
        'name': display_name[:255],
        'budget': budget,
        'labor_budget': labor_budget,
        'equipment_budget': equipment_budget,
        'material_budget': material_budget,
        'materials': materials,
        'dupa_breakdown': dupa_breakdown,
    }


def parse_dupa_xlsx(file_bytes):
    """Parse a DPWH DUPA `.xlsx` workbook into a list of Item of Work dicts."""
    try:
        zf = zipfile.ZipFile(io.BytesIO(file_bytes))
    except zipfile.BadZipFile as exc:
        raise ValueError('Upload a valid .xlsx Excel workbook.') from exc

    with zf:
        shared_strings = _read_shared_strings(zf)
        sheets = _read_workbook_sheets(zf)
        parsed = []
        for sheet_name, entry_path in sheets:
            rows = _read_sheet_grid(zf, entry_path, shared_strings)
            item = _parse_dupa_sheet(sheet_name, rows)
            if item is not None:
                parsed.append(item)
    return parsed


_INT_RE = re.compile(r'\d+')


def compute_week_schedule(project_start_date, weeks_text, days_value):
    """Turn ``(weeks_text, days_value)`` into ``(start_date, end_date, days_int)``.

    `weeks_text` can be a starting week (`"1"`, `"Week 1"`, `"W2"`) or a range
    (`"1-3"`, `"Week 2-4"`). `days_value` is the duration in calendar days; if
    omitted, the week range determines the span (default 7 days).
    """
    nums = [int(n) for n in _INT_RE.findall(str(weeks_text or '')) if int(n) >= 1]
    start_week = nums[0] if nums else 1
    end_week = nums[1] if len(nums) >= 2 and nums[1] >= start_week else None

    days_int = None
    if days_value is not None and str(days_value).strip() != '':
        dec = _to_decimal(days_value)
        if dec is not None and dec > 0:
            days_int = max(1, int(round(dec)))

    if project_start_date is None:
        return None, None, days_int

    start_date = project_start_date + timedelta(days=(start_week - 1) * 7)
    if days_int is not None:
        end_date = start_date + timedelta(days=days_int - 1)
    elif end_week is not None:
        end_date = project_start_date + timedelta(days=end_week * 7 - 1)
        days_int = (end_date - start_date).days + 1
    else:
        end_date = start_date + timedelta(days=6)
        days_int = 7
    return start_date, end_date, days_int


_BAR_CHART_STOP_MARKERS = (
    'total project cost',
    'monthly physical accomplishment',
    'weekly physical accomplishment',
    'monthly equivalent cost',
    'weekly equivalent cost',
)


def _to_positive_int(val):
    dec = _to_decimal(val)
    if dec is None or dec <= 0:
        return None
    return max(1, int(round(dec)))


def _parse_bar_chart_rows(rows, project_start_date):
    """Parse a DPWH SF-INFR-41 Bar Chart / PERT-CPM / S-Curve sheet.

    Returns a list of item dicts, or ``None`` if the sheet is not a bar chart.
    """
    header_idx = None
    duration_col = None
    day_start_col = None
    amount_col = None

    for idx, row in enumerate(rows[:45]):
        cand_dur = None
        cand_start = None
        cand_amt = None
        for col, text in _row_texts(row):
            tl = ' '.join(text.lower().split())
            if tl == 'duration' or tl.startswith('duration '):
                cand_dur = col
            elif 'day to start' in tl or 'start day' in tl:
                cand_start = col
            elif tl == 'amount' or tl == 'total amount':
                cand_amt = col
        if cand_dur is not None and cand_start is not None:
            header_idx = idx
            duration_col = cand_dur
            day_start_col = cand_start
            amount_col = cand_amt
            break

    if header_idx is None:
        return None

    # Locate Activity (Item No.) and Item Description columns on the header row or up to 3 rows below.
    activity_col = None
    desc_col = None
    data_start_idx = header_idx + 1
    for probe_idx in range(header_idx, min(len(rows), header_idx + 4)):
        for col, text in _row_texts(rows[probe_idx]):
            tl = ' '.join(text.lower().split())
            if tl in ('activity', 'item no', 'item no.', 'pay item no.', 'pay item'):
                activity_col = col
                data_start_idx = max(data_start_idx, probe_idx + 1)
            elif 'item description' in tl or tl in ('description', 'particulars'):
                desc_col = col
                data_start_idx = max(data_start_idx, probe_idx + 1)

    if activity_col is None:
        activity_col = 0
    if desc_col is None:
        desc_col = 1 if activity_col == 0 else activity_col + 1

    items = []
    for row in rows[data_start_idx:]:
        joined_lower = ' '.join(t.lower() for _, t in _row_texts(row))
        if any(marker in joined_lower for marker in _BAR_CHART_STOP_MARKERS):
            break

        duration = _to_positive_int(row.get(duration_col))
        if duration is None:
            continue
        day_to_start = _to_positive_int(row.get(day_start_col)) or 1

        item_no = (row.get(activity_col, '') or '').strip()
        description = (row.get(desc_col, '') or '').strip()
        if not item_no and not description:
            continue

        budget = _to_decimal(row.get(amount_col)) if amount_col is not None else None
        if budget is not None and budget < 0:
            budget = None

        w1 = (day_to_start - 1) // 7 + 1
        w2 = (day_to_start + duration - 2) // 7 + 1
        planned_weeks = f'Week {w1}' if w1 == w2 else f'Week {w1}-{w2}'

        if project_start_date is not None:
            start_date = project_start_date + timedelta(days=day_to_start - 1)
            end_date = start_date + timedelta(days=duration - 1)
        else:
            start_date = None
            end_date = None

        display_name = (
            f'{item_no} — {description}'
            if item_no and description and not description.lower().startswith(item_no.lower())
            else (description or item_no)
        )
        items.append({
            'item_no': item_no[:32],
            'name': display_name[:255],
            'budget': budget,
            'planned_weeks': planned_weeks[:32],
            'planned_days': duration,
            'day_to_start': day_to_start,
            'start_date': start_date,
            'end_date': end_date,
        })

    return items


def _parse_simple_schedule_rows(rows, project_start_date):
    """Parse a simple 3-column table (`Item of work` | `Weeks` | `Days`)."""
    item_col = None
    weeks_col = None
    days_col = None
    start_row_idx = 0

    for idx, row in enumerate(rows[:15]):
        ordered = _row_texts(row)
        cand_item = None
        cand_weeks = None
        cand_days = None
        for col, text in ordered:
            tl = text.lower().strip()
            if any(k in tl for k in ('item of work', 'item', 'work', 'category', 'scope', 'description')):
                if cand_item is None:
                    cand_item = col
            elif 'week' in tl:
                cand_weeks = col
            elif 'day' in tl or 'duration' in tl:
                cand_days = col
        if cand_item is not None and (cand_weeks is not None or cand_days is not None):
            item_col, weeks_col, days_col = cand_item, cand_weeks, cand_days
            start_row_idx = idx + 1
            break

    # Fallback: assume columns A, B, C when no explicit header row exists
    if item_col is None and rows:
        item_col, weeks_col, days_col = 0, 1, 2
        first_vals = ' '.join(rows[0].values()).lower()
        start_row_idx = 1 if ('item' in first_vals or 'week' in first_vals or 'day' in first_vals) else 0

    items = []
    for row in rows[start_row_idx:]:
        name = (row.get(item_col, '') if item_col is not None else '').strip()
        if not name:
            continue
        if name.lower() in ('total', 'grand total', 'item of work'):
            continue
        weeks_raw = (row.get(weeks_col, '') if weeks_col is not None else '').strip()
        days_raw = (row.get(days_col, '') if days_col is not None else '').strip()
        start_date, end_date, days_int = compute_week_schedule(
            project_start_date, weeks_raw, days_raw,
        )
        week_nums = [int(n) for n in _INT_RE.findall(str(weeks_raw or '')) if int(n) >= 1]
        day_to_start = ((week_nums[0] - 1) * 7 + 1) if week_nums else 1
        items.append({
            'item_no': '',
            'name': name[:255],
            'budget': None,
            'planned_weeks': weeks_raw[:32],
            'planned_days': days_int,
            'day_to_start': day_to_start,
            'start_date': start_date,
            'end_date': end_date,
        })
    return items


def _read_csv_grid(file_bytes):
    try:
        text = file_bytes.decode('utf-8-sig')
    except UnicodeDecodeError:
        text = file_bytes.decode('latin-1', errors='replace')
    rows = []
    for raw_row in csv.reader(io.StringIO(text)):
        row = {idx: val.strip() for idx, val in enumerate(raw_row) if val and val.strip()}
        if row:
            rows.append(row)
    return rows


def parse_items_schedule_workbook(file_bytes, project_start_date, sheet_name=None):
    """Parse either a DPWH SF-INFR-41 Bar Chart or a 3-column schedule workbook.

    Returns ``dict(items=..., sheet=..., sheets=..., format=...)``.
    """
    try:
        zf = zipfile.ZipFile(io.BytesIO(file_bytes))
    except zipfile.BadZipFile:
        # Allow CSV exports of either format
        rows = _read_csv_grid(file_bytes)
        if not rows:
            raise ValueError('Upload a valid .xlsx Excel workbook (or .csv file).')
        bar_items = _parse_bar_chart_rows(rows, project_start_date)
        if bar_items:
            return {
                'items': bar_items,
                'sheet': 'CSV',
                'sheets': ['CSV'],
                'format': 'bar_chart',
            }
        return {
            'items': _parse_simple_schedule_rows(rows, project_start_date),
            'sheet': 'CSV',
            'sheets': ['CSV'],
            'format': 'simple',
        }

    with zf:
        shared_strings = _read_shared_strings(zf)
        sheets = _read_workbook_sheets(zf)
        if not sheets:
            return {'items': [], 'sheet': None, 'sheets': [], 'format': 'simple'}

        sheet_grids = [
            (name, _read_sheet_grid(zf, entry_path, shared_strings))
            for name, entry_path in sheets
        ]

        # 1. Prefer DPWH SF-INFR-41 Bar Chart sheets
        bar_sheets = []
        for name, rows in sheet_grids:
            parsed = _parse_bar_chart_rows(rows, project_start_date)
            if parsed:
                bar_sheets.append((name, parsed))

        if bar_sheets:
            available = [name for name, _ in bar_sheets]
            if sheet_name:
                for name, parsed in bar_sheets:
                    if name == sheet_name:
                        return {
                            'items': parsed,
                            'sheet': name,
                            'sheets': available,
                            'format': 'bar_chart',
                        }
            first_name, first_items = bar_sheets[0]
            return {
                'items': first_items,
                'sheet': first_name,
                'sheets': available,
                'format': 'bar_chart',
            }

        # 2. Fall back to simple 3-column (Item of work | Weeks | Days)
        if sheet_name:
            for name, rows in sheet_grids:
                if name == sheet_name:
                    return {
                        'items': _parse_simple_schedule_rows(rows, project_start_date),
                        'sheet': name,
                        'sheets': [n for n, _ in sheet_grids],
                        'format': 'simple',
                    }
        for name, rows in sheet_grids:
            items = _parse_simple_schedule_rows(rows, project_start_date)
            if items:
                return {
                    'items': items,
                    'sheet': name,
                    'sheets': [n for n, _ in sheet_grids],
                    'format': 'simple',
                }

    return {'items': [], 'sheet': None, 'sheets': [], 'format': 'simple'}


def parse_items_schedule_xlsx(file_bytes, project_start_date, sheet_name=None):
    """Parse a DPWH SF-INFR-41 Bar Chart or 3-column schedule Excel file."""
    return parse_items_schedule_workbook(
        file_bytes, project_start_date, sheet_name=sheet_name,
    )['items']
