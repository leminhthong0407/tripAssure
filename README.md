# TripAssure Insurance Management System

A travel insurance management system built on MySQL 8.0 and Python,
developed as a final project for Introduction to Databases — NEU College
of Technology.

## Overview

TripAssure manages the complete operational lifecycle of travel insurance:
customer enrollment, contract issuance, claim processing, assessment, and
automated payout disbursement. Business rules are enforced entirely at the
database layer through stored procedures, triggers, and role-based access
control — the application layer handles only user interaction and display.

## Stack

- **Database:** MySQL 8.0
- **Backend / CLI:** Python 3.12+, mysql-connector-python, tabulate, python-dotenv
- **Web dashboard:** Streamlit, Plotly

## Database Schema

Nine third-normal-form tables across two dependency levels:

| Table | Role |
|---|---|
| `Customers` | Policyholder identity |
| `DestinationRegions` | Geographic risk multipliers |
| `InsurancePlans` | Product catalog with pricing and claim limits |
| `ClaimTypes` | Incident categories with per-type coverage rules |
| `Trips` | The insured event with its own lifecycle |
| `Contracts` | Binding agreement: customer × trip × plan |
| `Claims` | Compensation requests against a contract |
| `Assessments` | Assessor decisions (1:1 with Claims) |
| `Payouts` | Trigger-generated disbursement records |
| `AuditLog` | Immutable trail of all status changes |

## Project Structure

```
tripAssure/
├── sql/
│   ├── schema.sql              # DDL — tables, constraints, indexes
│   ├── advanced_objects.sql    # UDFs, views, stored procedures, triggers, RBAC
│   ├── sample_data.sql         # Seed data
│   ├── demo_script.sql         # End-to-end demo: enroll → contract → claim → payout
│   └── demo_audit.sql          # Security demo: audit trail across trigger chain
├── app/
│   ├── app.py                  # DB connection layer and all query functions
│   ├── web.py                  # Streamlit web dashboard (imports from app.py)
│   └── .env                    # Credentials — not committed to version control
├── docs/
│   └── report.pdf
├── .env.example                # Credential template
├── .gitignore
├── requirements.txt
└── README.md
```

## Setup

**Prerequisites:** MySQL 8.0+, Python 3.12+

**1. Clone and create virtual environment**
```bash
git clone <repo-url>
cd tripAssure
python -m venv venv
venv\Scripts\activate        # Windows
# source venv/bin/activate   # macOS / Linux
```

**2. Install dependencies**
```bash
pip install -r requirements.txt
```

**3. Configure credentials**
```bash
copy .env.example app\.env   # Windows
# cp .env.example app/.env   # macOS / Linux
```
Edit `app/.env` and fill in your MySQL credentials.

**4. Initialize the database (run in order)**
```bash
mysql -u root -p < sql/schema.sql
mysql -u root -p < sql/advanced_objects.sql
mysql -u root -p < sql/audit_log.sql
mysql -u root -p < sql/sample_data.sql
```

**5. Run**
```bash
# CLI
python app\app.py

# Web dashboard
python -m streamlit run app\web.py
```

## Demo Scripts

```bash
# Full end-to-end flow: enroll → contract → claim → assessment → payout → expiry
mysql -u root -p < sql/demo_script.sql

# Security demo: audit trail across trigger chain
mysql -u root -p < sql/demo_audit.sql
```

## Key Design Decisions

**Trips as a separate entity.** A trip has an independent lifecycle
(`upcoming → ongoing → completed`) tracked separately from its contract.
This enables trigger-based status synchronization and enforces the
one-trip-one-contract rule via `UNIQUE(TripID)`.

**Premium frozen at signing.** `TotalPremium` is stored as a fixed value
rather than computed dynamically — insurance contracts are legal documents
and the agreed premium must remain immutable even if the plan's base rate
changes later. Intentional denormalization.

**Database-enforced business rules.** Three triggers handle claim
validation before insert, automatic payout creation on assessment
approval, and contract status synchronization when a trip ends. No
application code can bypass these rules.

**RBAC enforced at the DB layer.** The web login maps each role to a
dedicated MySQL user (`tripAssure_agent`, `tripAssure_assessor`,
`tripAssure_admin`). Permissions are granted at the DB level — an agent
cannot insert assessments or read payouts regardless of what the
application layer does.

**Audit trail via trigger chain.** `AuditLog` captures every status
change on Contracts, Claims, and Payouts — including changes triggered
indirectly by other triggers — using `CURRENT_USER()` and `NOW()` at the
DB level. No application code is required to write audit records.

**Credentials via environment variables.** DB credentials are loaded from
`app/.env` at runtime using `python-dotenv`. The `.env` file is excluded
from version control. `get_connection()` resolves credentials from
Streamlit session state (web, role-specific user) or environment
variables (CLI), in that order.

## Author

Le Minh Thong — Student ID 11247227 — Class DS66B
Instructor: Dr. Tran Hung
National Economics University, College of Technology