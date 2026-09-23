# BuildPro CPMS — Construction Project Management System

Repo #2 of the **BuildPro** dual-entity ecosystem. Independent Django REST
backend for the construction firm, integrating with Repo #1 (hardware store POS)
over REST.

| System | Repo | Web port | DB port | Database |
|---|---|---|---|---|
| Hardware Store POS | `qb_pos_inventory_system` | 8000 | 5433 | `buildpro_pos` |
| **Construction CPMS** | **`qb_project_management_system`** | **8001** | **5434** | **`buildpro_cpms`** |

## Architecture

Two independent backends, one integration contract: **JWT Bearer tokens + REST**
for cross-system requisitions, material release tokens, and the collectibles ledger.

```
CPMS (this repo)  ──HTTP/JWT──▶  POS API  http://host.docker.internal:8000
 :8001                                  (requisition sync, release tokens, collectibles)
```

The CPMS container reaches the POS API through `extra_hosts:
host.docker.internal:host-gateway`, so no shared Docker network is required.

## Domain modules (`backend/apps/`)

| Module | Responsibility |
|---|---|
| `users` | Custom `User` with roles: Admin, Project Manager, Site Supervisor, Engineer |
| `projects` | Sites, contracts, project timelines (phases + milestones) |
| `site_inventory` | Site stock, small tools, heavy equipment tracking |
| `requisitions` | Field material requests and digital release-token generation for POS |
| `financials` | Budget vs actuals, project expense logs, utang/collectibles tracking |

## Quick start

```bash
cp backend/.env.example backend/.env      # optional: defaults work out of the box
docker compose up --build
```

- API root: http://localhost:8001/api/v1/
- Health check: http://localhost:8001/api/health/
- Admin: http://localhost:8001/admin/

## Common commands

```bash
docker compose exec backend python manage.py makemigrations
docker compose exec backend python manage.py migrate
docker compose exec backend python manage.py createsuperuser
docker compose exec backend python manage.py test
```

## Stack

Python 3.12 · Django 5.2 LTS · Django REST Framework 3.15 · SimpleJWT ·
PostgreSQL 15 · Docker