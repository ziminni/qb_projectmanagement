"""The demo dataset `seed_demo` loads — a Python mirror of the Flutter mocks.

Keep this file in step with the app it mirrors:

    flutter/lib/data/repositories/mock_data.dart          users, roles, projects,
                                                          assignments, categories, todos
    flutter/lib/data/repositories/mock_company_data.dart  company, clients, materials,
                                                          suppliers, trades, equipment
    flutter/lib/data/repositories/mock_labor_data.dart    workers, attendance

`pos_code` is *not* in the mocks. It is the POS selling unit with the same product
identity, written as the barcode POS's own `seed_demo` derives for that unit
(`QB{id:06}-{check digit}`, e.g. `QB000001-7`; see POS `apps/inventory/models.py`,
`planning/backend-integration/MAP.md`, task 5.1).

Only two demo materials have a POS equivalent: **Portland cement 40 kg**
(`QB000001-7`) and **Tile adhesive 25 kg**, which maps to the BAG unit `QB000010-9`
— never to the loose KG unit `QB000009-3`. The other ten stay `pos_code=None`,
because POS sells no such product: a made-up code comes back from the bridge as
`UNKNOWN_MATERIAL`, whereas a null one is refused by CPMS before the import
(`MISSING_POS_CODE`). Verify the codes against a live `GET integration/cpms/materials/`
whenever the POS demo catalog changes.

Money is written as `Decimal` strings, never floats, so no amount can arrive as
`Infinity`/`NaN`.
"""

from datetime import date

from .models import Role

# The single password every demo account signs in with (`MockData.demoPassword`).
DEMO_PASSWORD = 'password123'  # noqa: S105 - a demo fixture, not a credential

COMPANY = {
    'name': 'BuildRight Batangas Construction Inc.',
    'address': 'J.P. Laurel Highway, Lipa City, Batangas',
    'tin': '123-456-789-000',
    'pcab_license_no': 'PCAB 41234',
    'pcab_license_expiry': date(2026, 12, 15),
}

COMPANY_SETTINGS = {
    'default_retention_pct': '10.00',
    'default_down_payment_pct': '15.00',
    'behind_schedule_threshold_pct': '5.00',
}

USERS = [
    {'email': 'maria@example.ph', 'full_name': 'Maria Santos',
     'phone': '0917 555 0101', 'roles': [Role.ADMIN]},
    {'email': 'ramon@example.ph', 'full_name': 'Ramon Dela Cruz',
     'phone': '0917 555 0103', 'roles': [Role.OWNER]},
    {'email': 'ana@example.ph', 'full_name': 'Ana Bautista',
     'phone': '0917 555 0104', 'roles': [Role.SITE_ENGINEER]},
    {'email': 'liza@example.ph', 'full_name': 'Liza Garcia',
     'phone': '0917 555 0106', 'roles': [Role.ACCOUNTANT]},
    {'email': 'mark@example.ph', 'full_name': 'Mark Villanueva',
     'phone': '0917 555 0107', 'roles': [Role.CLIENT]},
    # A partner who runs a project and also works its site.
    {'email': 'elena@example.ph', 'full_name': 'Elena Torres',
     'phone': '0917 555 0108', 'roles': [Role.OWNER, Role.SITE_ENGINEER]},
]

CLIENTS = [
    {'name': 'Mark Villanueva', 'contact_person': 'Mark Villanueva',
     'email': 'mark@example.ph', 'phone': '0917 555 0107',
     'address': 'Brgy. Sabang, Lipa City', 'user': 'mark@example.ph'},
    {'name': 'Tanauan Logistics Corp.', 'contact_person': 'Grace Lim',
     'email': 'grace@tlc.example.ph', 'phone': '043 555 0120',
     'address': 'Sto. Tomas, Batangas', 'user': None},
    {'name': 'Our Lady of Peace Clinic', 'contact_person': 'Dr. Paolo Cruz',
     'email': '', 'phone': '043 555 0133',
     'address': 'Tanauan City, Batangas', 'user': None},
]

MATERIALS = [
    {'name': 'Portland cement 40 kg', 'unit': 'bag', 'default_unit_cost': '260.00',
     'store_sku': 'CEM-40', 'pos_code': 'QB000001-7'},  # POS Portland Cement 40kg
    {'name': 'Deformed bar 10 mm × 6 m', 'unit': 'pc', 'default_unit_cost': '230.00',
     'store_sku': 'RB-10', 'pos_code': None},
    {'name': 'Deformed bar 12 mm × 6 m', 'unit': 'pc', 'default_unit_cost': '330.00',
     'store_sku': 'RB-12', 'pos_code': None},
    {'name': 'Washed sand', 'unit': 'cu.m', 'default_unit_cost': '1300.00',
     'store_sku': None, 'pos_code': None},
    {'name': 'Gravel 3/4"', 'unit': 'cu.m', 'default_unit_cost': '1500.00',
     'store_sku': None, 'pos_code': None},
    {'name': 'CHB 4"', 'unit': 'pc', 'default_unit_cost': '18.00',
     'store_sku': 'CHB-4', 'pos_code': None},
    {'name': 'Marine plywood 1/2"', 'unit': 'sheet', 'default_unit_cost': '750.00',
     'store_sku': 'PLY-12', 'pos_code': None},
    {'name': 'Coco lumber 2×3×10', 'unit': 'pc', 'default_unit_cost': '110.00',
     'store_sku': None, 'pos_code': None},
    {'name': 'Tie wire #16', 'unit': 'kg', 'default_unit_cost': '95.00',
     'store_sku': 'TW-16', 'pos_code': None},
    {'name': 'Long-span roof sheet 0.5 mm', 'unit': 'lin.m',
     'default_unit_cost': '450.00', 'store_sku': None, 'pos_code': None},
    {'name': 'Floor tile 60×60', 'unit': 'sq.m', 'default_unit_cost': '650.00',
     'store_sku': None, 'pos_code': None},
    {'name': 'Tile adhesive 25 kg', 'unit': 'bag', 'default_unit_cost': '380.00',
     'store_sku': 'TA-25', 'pos_code': 'QB000010-9'},  # POS Tile Adhesive BAG, not KG
]

SUPPLIERS = [
    {'name': 'BuildRight Hardware (own store)', 'contact_person': 'Store counter',
     'phone': '043 555 0150', 'address': 'Lipa City', 'is_own_store': True},
    {'name': 'Batangas Steel Supply', 'contact_person': 'Rico Tan',
     'phone': '043 555 0161', 'address': 'Batangas City', 'is_own_store': False},
    {'name': 'Lipa Aggregates Trading', 'contact_person': 'Nora Dimaculangan',
     'phone': '043 555 0172', 'address': 'Lipa City', 'is_own_store': False},
    {'name': 'Southern Roofing Corp.', 'contact_person': 'Allan Uy',
     'phone': '043 555 0183', 'address': 'Sto. Tomas, Batangas', 'is_own_store': False},
]

TRADES = [
    'Mason', 'Carpenter', 'Steelman', 'Laborer', 'Electrician',
    'Plumber', 'Painter', 'Tile setter', 'Welder',
]

EQUIPMENT = [
    {'name': 'One-bagger concrete mixer', 'ownership': 'owned', 'rate': '800.00',
     'rate_unit': 'day'},
    {'name': 'Plate compactor', 'ownership': 'rented', 'rate': '1200.00',
     'rate_unit': 'day'},
    {'name': 'Bar cutter', 'ownership': 'owned', 'rate': '300.00', 'rate_unit': 'day'},
    {'name': 'Backhoe', 'ownership': 'rented', 'rate': '1800.00', 'rate_unit': 'hour'},
]

# `status` uses the wire codes in `ProjectStatus`; `start`/`end` are ISO dates.
PROJECTS = [
    {
        'code': 'QB-2026-014', 'name': 'Two-storey residence, Villanueva',
        'location': 'Lipa City, Batangas', 'latitude': '13.941100',
        'longitude': '121.163100', 'client': 'Mark Villanueva',
        'contract_amount': '2000000.00', 'down_payment_pct': '15.00',
        'retention_pct': '10.00', 'start': date(2026, 8, 3),
        'target_end': date(2027, 1, 29), 'status': 'ongoing',
    },
    {
        'code': 'QB-2026-018', 'name': 'Warehouse extension',
        'location': 'Sto. Tomas, Batangas', 'latitude': '14.107800',
        'longitude': '121.141600', 'client': 'Tanauan Logistics Corp.',
        'contract_amount': '3500000.00', 'down_payment_pct': '20.00',
        'retention_pct': '10.00', 'start': date(2026, 9, 7),
        'target_end': date(2027, 3, 26), 'status': 'ongoing',
    },
    {
        'code': 'QB-2026-021', 'name': 'Clinic renovation',
        'location': 'Tanauan City, Batangas', 'latitude': '14.086300',
        'longitude': '121.149500', 'client': 'Our Lady of Peace Clinic',
        'contract_amount': '1250000.00', 'down_payment_pct': '15.00',
        'retention_pct': '10.00', 'start': date(2026, 11, 9),
        'target_end': date(2027, 2, 26), 'status': 'accepted',
    },
    # Sent to Mark; Ana gets it once Mark accepts.
    {
        'code': 'QB-2026-025', 'name': 'Townhouse row, Malvar',
        'location': 'Malvar, Batangas', 'latitude': '14.044700',
        'longitude': '121.158800', 'client': 'Mark Villanueva',
        'contract_amount': '6800000.00', 'down_payment_pct': '15.00',
        'retention_pct': '10.00', 'start': date(2027, 1, 11),
        'target_end': date(2027, 9, 30), 'status': 'requested',
    },
]

# (project code, account email, role on project, request response)
ASSIGNMENTS = [
    ('QB-2026-014', 'ramon@example.ph', 'owner', 'accepted'),
    ('QB-2026-014', 'ana@example.ph', 'site_engineer', 'accepted'),
    ('QB-2026-014', 'mark@example.ph', 'client', 'accepted'),
    ('QB-2026-018', 'ramon@example.ph', 'owner', 'accepted'),
    ('QB-2026-018', 'elena@example.ph', 'site_engineer', 'accepted'),
    ('QB-2026-021', 'elena@example.ph', 'owner', 'accepted'),
    ('QB-2026-021', 'elena@example.ph', 'site_engineer', 'accepted'),
    ('QB-2026-025', 'ramon@example.ph', 'owner', 'accepted'),
    ('QB-2026-025', 'mark@example.ph', 'client', 'pending'),
    ('QB-2026-025', 'ana@example.ph', 'site_engineer', 'not_sent'),
]

# project code → [(name, budget or None, sort_order)]
CATEGORIES = {
    'QB-2026-014': [
        ('Foundation', '500000.00', 1),
        ('Pillars', '400000.00', 2),
        ('Roofing', '600000.00', 3),
        ('Tiling', '500000.00', 4),
    ],
    'QB-2026-018': [
        ('Site preparation', '400000.00', 1),
        ('Steel frame', '1800000.00', 2),
        # No budget yet, so the project falls back to equal weights.
        ('Roofing', None, 3),
        ('Electrical', '300000.00', 4),
    ],
}

# (category name, title, start date, end date, state) under project QB-2026-014.
# `state` is 'verified', 'done' or 'open'.
TODOS = {
    'QB-2026-014': [
        ('Foundation', 'Excavation', date(2026, 8, 3), date(2026, 8, 8), 'verified'),
        ('Foundation', 'Rebar installation', date(2026, 8, 10), date(2026, 8, 19), 'verified'),
        ('Foundation', 'Formworks', date(2026, 8, 17), date(2026, 8, 26), 'verified'),
        ('Foundation', 'Concrete pouring', date(2026, 8, 27), date(2026, 9, 2), 'verified'),
        ('Pillars', 'Ground-floor column rebar',
         date(2026, 9, 3), date(2026, 9, 12), 'verified'),
        ('Pillars', 'Ground-floor column formworks',
         date(2026, 9, 10), date(2026, 9, 19), 'verified'),
        ('Pillars', 'Ground-floor column pouring',
         date(2026, 9, 21), date(2026, 9, 26), 'verified'),
        ('Pillars', 'Second-floor column rebar',
         date(2026, 9, 28), date(2026, 10, 14), 'done'),
        ('Pillars', 'Second-floor column pouring',
         date(2026, 10, 19), date(2026, 10, 31), 'open'),
        ('Roofing', 'Roof beams', date(2026, 11, 2), date(2026, 11, 14), 'open'),
        ('Roofing', 'Truss fabrication', date(2026, 11, 9), date(2026, 11, 21), 'open'),
        ('Roofing', 'Truss installation', date(2026, 11, 23), date(2026, 12, 5), 'open'),
        ('Roofing', 'Purlins', date(2026, 12, 7), date(2026, 12, 12), 'open'),
        ('Roofing', 'Roof sheets', date(2026, 12, 14), date(2026, 12, 23), 'open'),
        ('Roofing', 'Flashing and gutters', date(2027, 1, 4), date(2027, 1, 9), 'open'),
        ('Tiling', 'Floor screeding', date(2027, 1, 4), date(2027, 1, 12), 'open'),
        ('Tiling', 'Floor tiling', date(2027, 1, 11), date(2027, 1, 22), 'open'),
        ('Tiling', 'Wall tiling', date(2027, 1, 18), date(2027, 1, 28), 'open'),
    ],
    'QB-2026-018': [
        ('Site preparation', 'Clearing and grubbing',
         date(2026, 9, 7), date(2026, 9, 11), 'verified'),
        ('Site preparation', 'Layout and batter boards',
         date(2026, 9, 14), date(2026, 9, 16), 'verified'),
        ('Steel frame', 'Footings', date(2026, 9, 17), date(2026, 10, 2), 'verified'),
        ('Steel frame', 'Column erection',
         date(2026, 10, 5), date(2026, 10, 23), 'done'),
        ('Steel frame', 'Beam erection', date(2026, 10, 26), date(2026, 11, 20), 'open'),
        ('Roofing', 'Purlins', date(2026, 11, 23), date(2026, 12, 4), 'open'),
        ('Roofing', 'Roof sheets', date(2026, 12, 7), date(2026, 12, 23), 'open'),
        ('Electrical', 'Rough-in', date(2027, 1, 4), date(2027, 2, 5), 'open'),
        ('Electrical', 'Fixtures', date(2027, 2, 8), date(2027, 3, 12), 'open'),
    ],
}

# Who ticked a to-do off / verified it (`done_by` / `verified_by` in the mock).
TODO_CLOSED_BY = 'ana@example.ph'
TODO_VERIFIED_BY = 'ramon@example.ph'

# (full name, trade, daily rate, SSS no., PhilHealth no., Pag-IBIG no., is_active)
WORKERS = [
    ('Rodel Macaraig', 'Mason', '750.00', '34-1234561-1', '12-345678901-1',
     '1211-0000-0001', True),
    ('Arnel Dimaano', 'Mason', '750.00', '34-1234562-2', '12-345678902-2',
     '1211-0000-0002', True),
    ('Jun Villanueva', 'Steelman', '750.00', '34-1234563-3', '12-345678903-3',
     '1211-0000-0003', True),
    ('Bong Perez', 'Carpenter', '750.00', '34-1234564-4', '12-345678904-4',
     '1211-0000-0004', True),
    ('Leo Mercado', 'Laborer', '610.00', '34-1234565-5', None, None, True),
    ('Dodong Castillo', 'Laborer', '610.00', '34-1234566-6', None, None, True),
    ('Nilo Aguilar', 'Laborer', '610.00', None, None, None, True),
    ('Ramil Cruz', 'Welder', '850.00', '34-1234568-8', '12-345678908-8', None, True),
    ('Ernesto Lopez', 'Welder', '850.00', '34-1234569-9', None, None, True),
    ('Toto Ramos', 'Laborer', '610.00', None, None, None, True),
    ('Pablo Garcia', 'Electrician', '800.00', None, None, None, False),
]

# Attendance: the mock generates six-day weeks from Oct 1 to Oct 24, 2026; the
# demo only needs the first few working days (`ATTENDANCE_WORKING_DAYS`) so the
# payroll screens have data without 200 rows nobody looks at.
ATTENDANCE_FIRST_DAY = date(2026, 10, 1)
ATTENDANCE_WORKING_DAYS = 3
# (project code, worker indexes into WORKERS (1-based), recording account)
ATTENDANCE_GROUPS = [
    ('QB-2026-014', [1, 2, 3, 4, 5, 6, 7], 'ana@example.ph'),
    ('QB-2026-018', [8, 9, 10], 'elena@example.ph'),
]
