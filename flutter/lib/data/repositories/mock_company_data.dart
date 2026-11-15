import '../models/client.dart';
import '../models/company.dart';
import '../models/company_settings.dart';
import '../models/equipment.dart';
import '../models/material_item.dart';
import '../models/supplier.dart';
import '../models/trade.dart';

/// Seed data for the company profile, settings and master lists.
abstract final class MockCompanyData {
  static final company = Company(
    id: 1,
    name: 'BuildRight Batangas Construction Inc.',
    address: 'J.P. Laurel Highway, Lipa City, Batangas',
    tin: '123-456-789-000',
    pcabLicenseNo: 'PCAB 41234',
    pcabLicenseExpiry: DateTime(2026, 12, 15),
  );

  static const settings = CompanySettings(
    id: 1,
    companyId: 1,
    defaultRetentionPct: 10,
    defaultDownPaymentPct: 15,
    behindScheduleThresholdPct: 5,
  );

  static const clients = [
    Client(
      id: 1,
      name: 'Mark Villanueva',
      contactPerson: 'Mark Villanueva',
      email: 'mark@example.ph',
      phone: '0917 555 0107',
      address: 'Brgy. Sabang, Lipa City',
      userId: 7,
    ),
    Client(
      id: 2,
      name: 'Tanauan Logistics Corp.',
      contactPerson: 'Grace Lim',
      email: 'grace@tlc.example.ph',
      phone: '043 555 0120',
      address: 'Sto. Tomas, Batangas',
    ),
    Client(
      id: 3,
      name: 'Our Lady of Peace Clinic',
      contactPerson: 'Dr. Paolo Cruz',
      phone: '043 555 0133',
      address: 'Tanauan City, Batangas',
    ),
  ];

  static const materials = [
    MaterialItem(
      id: 1,
      name: 'Portland cement 40 kg',
      unit: 'bag',
      defaultUnitCost: 260,
      storeSku: 'CEM-40',
    ),
    MaterialItem(
      id: 2,
      name: 'Deformed bar 10 mm × 6 m',
      unit: 'pc',
      defaultUnitCost: 230,
      storeSku: 'RB-10',
    ),
    MaterialItem(
      id: 3,
      name: 'Deformed bar 12 mm × 6 m',
      unit: 'pc',
      defaultUnitCost: 330,
      storeSku: 'RB-12',
    ),
    MaterialItem(
      id: 4,
      name: 'Washed sand',
      unit: 'cu.m',
      defaultUnitCost: 1300,
    ),
    MaterialItem(
      id: 5,
      name: 'Gravel 3/4"',
      unit: 'cu.m',
      defaultUnitCost: 1500,
    ),
    MaterialItem(
      id: 6,
      name: 'CHB 4"',
      unit: 'pc',
      defaultUnitCost: 18,
      storeSku: 'CHB-4',
    ),
    MaterialItem(
      id: 7,
      name: 'Marine plywood 1/2"',
      unit: 'sheet',
      defaultUnitCost: 750,
      storeSku: 'PLY-12',
    ),
    MaterialItem(
      id: 8,
      name: 'Coco lumber 2×3×10',
      unit: 'pc',
      defaultUnitCost: 110,
    ),
    MaterialItem(
      id: 9,
      name: 'Tie wire #16',
      unit: 'kg',
      defaultUnitCost: 95,
      storeSku: 'TW-16',
    ),
    MaterialItem(
      id: 10,
      name: 'Long-span roof sheet 0.5 mm',
      unit: 'lin.m',
      defaultUnitCost: 450,
    ),
    MaterialItem(
      id: 11,
      name: 'Floor tile 60×60',
      unit: 'sq.m',
      defaultUnitCost: 650,
    ),
    MaterialItem(
      id: 12,
      name: 'Tile adhesive 25 kg',
      unit: 'bag',
      defaultUnitCost: 380,
      storeSku: 'TA-25',
    ),
  ];

  static const suppliers = [
    Supplier(
      id: 1,
      name: 'BuildRight Hardware (own store)',
      contactPerson: 'Store counter',
      phone: '043 555 0150',
      address: 'Lipa City',
      isOwnStore: true,
    ),
    Supplier(
      id: 2,
      name: 'Batangas Steel Supply',
      contactPerson: 'Rico Tan',
      phone: '043 555 0161',
      address: 'Batangas City',
    ),
    Supplier(
      id: 3,
      name: 'Lipa Aggregates Trading',
      contactPerson: 'Nora Dimaculangan',
      phone: '043 555 0172',
      address: 'Lipa City',
    ),
    Supplier(
      id: 4,
      name: 'Southern Roofing Corp.',
      contactPerson: 'Allan Uy',
      phone: '043 555 0183',
      address: 'Sto. Tomas, Batangas',
    ),
  ];

  static const trades = [
    Trade(id: 1, name: 'Mason'),
    Trade(id: 2, name: 'Carpenter'),
    Trade(id: 3, name: 'Steelman'),
    Trade(id: 4, name: 'Laborer'),
    Trade(id: 5, name: 'Electrician'),
    Trade(id: 6, name: 'Plumber'),
    Trade(id: 7, name: 'Painter'),
    Trade(id: 8, name: 'Tile setter'),
    Trade(id: 9, name: 'Welder'),
  ];

  static const equipment = [
    Equipment(
      id: 1,
      name: 'One-bagger concrete mixer',
      ownership: EquipmentOwnership.owned,
      rate: 800,
      rateUnit: RateUnit.day,
    ),
    Equipment(
      id: 2,
      name: 'Plate compactor',
      ownership: EquipmentOwnership.rented,
      rate: 1200,
      rateUnit: RateUnit.day,
    ),
    Equipment(
      id: 3,
      name: 'Bar cutter',
      ownership: EquipmentOwnership.owned,
      rate: 300,
      rateUnit: RateUnit.day,
    ),
    Equipment(
      id: 4,
      name: 'Backhoe',
      ownership: EquipmentOwnership.rented,
      rate: 1800,
      rateUnit: RateUnit.hour,
    ),
  ];
}
