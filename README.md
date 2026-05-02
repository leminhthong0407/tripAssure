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
- **Backend / CLI:** Python 3.12, mysql-connector-python, tabulate
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

## Setup

**Prerequisites:** MySQL 8.0+, Python 3.12+

```bash
# 1. Create schema and seed data (run in order)
mysql -u root -p < sql/schema.sql
mysql -u root -p < sql/advanced_objects.sql
mysql -u root -p < sql/sample_data.sql

# 2. Install Python dependencies
pip install mysql-connector-python tabulate streamlit plotly

# 3a. Run CLI
python app/app.py

# 3b. Run web dashboard
streamlit run app/web.py
```

## Key Design Decisions

**Trips as a separate entity.** A trip has an independent lifecycle
(`upcoming → ongoing → completed`) that must be tracked separately from
its contract. This enables trigger-based status synchronization and
enforces the one-trip-one-contract rule via `UNIQUE(TripID)`.

**Premium frozen at signing.** `TotalPremium` is stored as a fixed value
rather than computed on the fly — insurance contracts are legal documents
and the agreed premium must remain immutable even if the plan's base rate
changes later.

**Database-enforced business rules.** Three triggers handle: claim
validation before insert, automatic payout creation on assessment
approval, and contract status synchronization when a trip ends. No
application code can bypass these rules.

## Project Structure
```text
├── sql/
│   ├── schema.sql            # 3NF Table definitions & constraints
│   ├── advanced_objects.sql  # Triggers, Procedures, Views, & UDFs
│   └── sample_data.sql       # Seed data for system testing
├── app/
│   ├── app.py                # DB connection & core query functions
│   └── web.py                # Streamlit web interface (UI layer)
├── docs/
│   └── report.pdf            # Final project documentation
└── README.md                 # Project overview & setup instructions
```
## Author

Le Minh Thong — Student ID 11247227 — Class DS66B  
Instructor: Dr. Tran Hung  
National Economics University, College of Technology
