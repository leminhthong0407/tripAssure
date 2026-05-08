"""
TripAssure Travel Insurance Management System
Python Application — Backend & CLI

Run: python app.py
Requires: pip install mysql-connector-python tabulate python-dotenv

Credentials: copy .env.example → .env and fill in values.
Never commit .env to version control.
"""

import os
from pathlib import Path
from dotenv import load_dotenv

# Tìm .env tương đối với vị trí app.py — không phụ thuộc working directory
load_dotenv(dotenv_path=Path(__file__).parent / ".env")

def _require_env(key: str) -> str:
    """Đọc biến môi trường bắt buộc. Fail fast nếu thiếu — tránh chạy với config sai."""
    val = os.getenv(key)
    if not val:
        raise EnvironmentError(
            f"Required environment variable '{key}' is not set. "
            f"Copy .env.example to .env and fill in the values."
        )
    return val

DB_CONFIG = {
    "host":     os.getenv("DB_HOST", "localhost"),
    "port":     int(os.getenv("DB_PORT", "3306")),
    "database": os.getenv("DB_NAME", "TravelInsuranceDB"),
    "autocommit": False,
    # user/password intentionally omitted here —
    # resolved at connection time via get_connection()
}

import mysql.connector
from contextlib import contextmanager
from decimal import Decimal, InvalidOperation

def get_connection():
    """
    Resolve DB credentials at connection time.

    Priority:
      1. Streamlit session state (web layer — role-specific DB user)
      2. Environment variables DB_USER / DB_PASSWORD (CLI layer)

    This separation ensures:
      - Web: each role connects as its own DB user → RBAC enforced at DB level
      - CLI: uses env var credentials (typically admin for demo/dev)
    """
    try:
        import streamlit as st
        user     = st.session_state.get("db_user")
        password = st.session_state.get("db_pass")
    except Exception:
        user, password = None, None

    # Fallback to environment variables if not in a Streamlit session
    if not user:
        user     = _require_env("DB_USER")
        password = _require_env("DB_PASSWORD")

    return mysql.connector.connect(**DB_CONFIG, user=user, password=password)


def _clean_error(e):
    """
    Strip MySQL error codes from exception messages.
    '1644 (45000): Claim denied: ...' → 'Claim denied: ...'
    """
    msg = str(e)
    # mysql.connector wraps SIGNAL messages as: NNNN (45000): actual message
    if "): " in msg:
        return msg.split("): ", 1)[1]
    return msg


@contextmanager
def _cursor():
    """
    Read-only / simple-write context manager.
    Provides a (conn, cur) pair. Commits on clean exit,
    rolls back on exception. Used for plain INSERTs/SELECTs
    that do NOT call a stored procedure with OUT params.
    """
    conn = get_connection()
    cur  = conn.cursor(dictionary=True)
    try:
        yield conn, cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


@contextmanager
def _sp_cursor():
    """
    Stored-procedure context manager.
    After CALL, consumes any extra result sets with nextset()
    so the cursor is clean before the subsequent SELECT of
    OUT-param variables. Commits on clean exit.

    Background: mysql-connector-python raises
    'Unread result found' if result sets from a CALL are not
    fully consumed before the next execute(). nextset() drains
    them. This does NOT apply to plain SELECT/INSERT.
    """
    conn = get_connection()
    cur  = conn.cursor(dictionary=True)
    try:
        yield conn, cur
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        cur.close()
        conn.close()


# ============================================================
# enrollment.py — Customer registration
# ============================================================
def create_customer(full_name, dob, national_id, phone, email=None, address=None):
    """
    Registers a new customer. Returns the new CustomerID.
    Raises mysql.connector.IntegrityError if NationalID exists.
    """
    sql = """
        INSERT INTO Customers
            (FullName, DateOfBirth, NationalID, Phone, Email, Address)
        VALUES (%s, %s, %s, %s, %s, %s)
    """
    with _cursor() as (conn, cur):
        cur.execute(sql, (full_name, dob, national_id, phone, email, address))
        return cur.lastrowid


def find_customer(search_term):
    """Searches by partial name or exact NationalID."""
    sql = """
        SELECT CustomerID, FullName, DateOfBirth, NationalID, Phone, Email
        FROM   Customers
        WHERE  FullName LIKE %s OR NationalID = %s
    """
    with _cursor() as (_, cur):
        cur.execute(sql, (f"%{search_term}%", search_term))
        return cur.fetchall()


# ============================================================
# contracts.py — Contract management
# ============================================================
def get_plans():
    """Returns all active insurance plans."""
    with _cursor() as (_, cur):
        cur.execute("SELECT * FROM InsurancePlans WHERE IsActive = TRUE")
        return cur.fetchall()


def get_regions():
    """Returns all destination regions ordered by multiplier."""
    with _cursor() as (_, cur):
        cur.execute("SELECT * FROM DestinationRegions ORDER BY PremiumMultiplier")
        return cur.fetchall()


def preview_premium(plan_id, trip_id):
    """Calls fn_CalculatePremium for a pre-confirmation preview."""
    with _cursor() as (_, cur):
        cur.execute("SELECT fn_CalculatePremium(%s, %s) AS Premium", (plan_id, trip_id))
        row = cur.fetchone()
        return row["Premium"] if row else Decimal("0")


def create_trip(destination, region_id, departure, return_date, num_travelers):
    """Inserts a new trip. Returns TripID."""
    sql = """
        INSERT INTO Trips
            (Destination, RegionID, DepartureDate, ReturnDate, NumTravelers, TripStatus)
        VALUES (%s, %s, %s, %s, %s, 'upcoming')
    """
    with _cursor() as (conn, cur):
        cur.execute(sql, (destination, region_id, departure, return_date, num_travelers))
        return cur.lastrowid


def create_contract(customer_id, trip_id, plan_id):
    """
    Calls sp_CreateContract.
    Returns (contract_id, total_premium) or raises on failure.

    After CALL, nextset() drains the SP's internal result sets
    before we SELECT the OUT-param session variables.
    """
    with _sp_cursor() as (conn, cur):
        cur.execute(
            "CALL sp_CreateContract(%s, %s, %s, @cid, @premium)",
            (customer_id, trip_id, plan_id)
        )
        # Drain any extra result sets left by the stored procedure
        while cur.nextset():
            pass
        cur.execute("SELECT @cid AS ContractID, @premium AS TotalPremium")
        row = cur.fetchone()
        return row["ContractID"], row["TotalPremium"]


def get_active_contracts():
    """Returns vw_ActiveContracts."""
    with _cursor() as (_, cur):
        cur.execute("SELECT * FROM vw_ActiveContracts")
        return cur.fetchall()


# ============================================================
# claims.py — Claim filing
# ============================================================
def get_claim_types():
    """Returns all claim types with coverage details."""
    with _cursor() as (_, cur):
        cur.execute("SELECT * FROM ClaimTypes")
        return cur.fetchall()


def file_claim(contract_id, claim_type_id, description):
    """
    Calls sp_FileClaim. Returns new ClaimID.
    BEFORE INSERT trigger enforces:
      - contract is active
      - annual claim count ≤ MaxClaimsPerYear
    """
    with _sp_cursor() as (conn, cur):
        cur.execute(
            "CALL sp_FileClaim(%s, %s, %s, @claimid)",
            (contract_id, claim_type_id, description)
        )
        while cur.nextset():
            pass
        cur.execute("SELECT @claimid AS ClaimID")
        return cur.fetchone()["ClaimID"]


def get_pending_claims():
    """Returns vw_PendingClaims for the assessor queue."""
    with _cursor() as (_, cur):
        cur.execute("SELECT * FROM vw_PendingClaims")
        return cur.fetchall()


# ============================================================
# assessment.py — Assessor decisions
# ============================================================
def process_assessment(claim_id, result, approved_amount, note):
    """
    Calls sp_ProcessAssessment.
    AFTER INSERT trigger on Assessments auto-creates a Payout if approved.
    approved_amount: Decimal — use Decimal, not float, for financial values.
    """
    with _sp_cursor() as (conn, cur):
        cur.execute(
            "CALL sp_ProcessAssessment(%s, %s, %s, %s)",
            (claim_id, result, approved_amount, note)
        )
        while cur.nextset():
            pass


def get_claim_detail(claim_id):
    """Returns full claim detail including assessment and payout."""
    sql = """
        SELECT
            cl.ClaimID,
            cl.FilingDate,
            cl.ClaimStatus,
            cl.IncidentDescription,
            ct.TypeName             AS ClaimType,
            ct.CoveragePercentage,
            ct.MaxCoverageAmount,
            cu.FullName             AS CustomerName,
            t.Destination,
            a.Result                AS AssessmentResult,
            a.ApprovedAmount,
            a.AssessorNote,
            p.Amount                AS PayoutAmount,
            p.PayoutDate,
            p.PaymentMethod
        FROM   Claims cl
        JOIN   Contracts    c   ON cl.ContractID  = c.ContractID
        JOIN   Customers    cu  ON c.CustomerID   = cu.CustomerID
        JOIN   Trips        t   ON c.TripID       = t.TripID
        JOIN   ClaimTypes   ct  ON cl.ClaimTypeID = ct.ClaimTypeID
        LEFT JOIN Assessments a ON cl.ClaimID     = a.ClaimID
        LEFT JOIN Payouts     p ON cl.ClaimID     = p.ClaimID
        WHERE  cl.ClaimID = %s
    """
    with _cursor() as (_, cur):
        cur.execute(sql, (claim_id,))
        return cur.fetchone()


# ============================================================
# reports.py — Admin reports
# ============================================================
def report_monthly_payouts():
    with _cursor() as (_, cur):
        cur.execute("SELECT * FROM vw_MonthlyPayoutSummary")
        return cur.fetchall()


def report_contract_claim_summary():
    with _cursor() as (_, cur):
        cur.execute("SELECT * FROM vw_ContractClaimSummary ORDER BY TotalPaidOutVND DESC")
        return cur.fetchall()


def report_success_rate_by_claim_type():
    sql = """
        SELECT
            ct.TypeName,
            COUNT(cl.ClaimID)                                           AS TotalClaims,
            SUM(CASE WHEN a.Result = 'approved' THEN 1 ELSE 0 END)     AS Approved,
            SUM(CASE WHEN a.Result = 'rejected' THEN 1 ELSE 0 END)     AS Rejected,
            ROUND(
                SUM(CASE WHEN a.Result = 'approved' THEN 1 ELSE 0 END)
                / NULLIF(COUNT(cl.ClaimID), 0) * 100, 1
            )                                                           AS ApprovalRatePct,
            COALESCE(SUM(p.Amount), 0)                                  AS TotalPaidOutVND
        FROM ClaimTypes ct
        LEFT JOIN Claims      cl ON ct.ClaimTypeID = cl.ClaimTypeID
        LEFT JOIN Assessments a  ON cl.ClaimID     = a.ClaimID
        LEFT JOIN Payouts     p  ON cl.ClaimID     = p.ClaimID
        GROUP BY ct.ClaimTypeID, ct.TypeName
        ORDER BY TotalClaims DESC
    """
    with _cursor() as (_, cur):
        cur.execute(sql)
        return cur.fetchall()


def report_upcoming_expiries(days_ahead=30):
    sql = """
        SELECT
            c.ContractID,
            cu.FullName,
            cu.Phone,
            t.Destination,
            t.ReturnDate,
            DATEDIFF(t.ReturnDate, CURDATE()) AS DaysUntilExpiry,
            p.PlanName
        FROM Contracts      c
        JOIN Customers      cu ON c.CustomerID = cu.CustomerID
        JOIN Trips          t  ON c.TripID     = t.TripID
        JOIN InsurancePlans p  ON c.PlanID     = p.PlanID
        WHERE c.ContractStatus = 'active'
          AND t.ReturnDate BETWEEN CURDATE()
                               AND DATE_ADD(CURDATE(), INTERVAL %s DAY)
        ORDER BY t.ReturnDate ASC
    """
    with _cursor() as (_, cur):
        cur.execute(sql, (days_ahead,))
        return cur.fetchall()


# ============================================================
# main.py — CLI menu
# ============================================================
from tabulate import tabulate


def fmt(rows, headers="keys"):
    """Tabulate helper — prints dict rows as a clean table."""
    if not rows:
        print("  (no records found)\n")
        return
    print(tabulate(rows, headers=headers, tablefmt="rounded_outline", floatfmt=",.0f"))
    print()


def _input_date(prompt):
    """Prompt for a date string; retry until format is valid."""
    import datetime
    while True:
        raw = input(prompt).strip()
        try:
            datetime.date.fromisoformat(raw)
            return raw
        except ValueError:
            print("  ✗ Invalid format. Please use YYYY-MM-DD (e.g. 2026-09-01).")


def _input_int(prompt):
    """Prompt for an integer; retry on bad input."""
    while True:
        raw = input(prompt).strip()
        try:
            return int(raw)
        except ValueError:
            print("  ✗ Please enter a whole number.")


def _input_decimal(prompt):
    """Prompt for a Decimal; retry on bad input. Used for money."""
    while True:
        raw = input(prompt).strip()
        try:
            return Decimal(raw)
        except InvalidOperation:
            print("  ✗ Please enter a valid number (e.g. 4500000).")


def menu_enroll():
    print("\n── NEW CUSTOMER ENROLLMENT ──")
    name    = input("Full name         : ").strip()
    dob     = _input_date("Date of birth     : (YYYY-MM-DD) ")
    nid     = input("National ID       : ").strip()
    phone   = input("Phone             : ").strip()
    email   = input("Email  (optional) : ").strip() or None
    address = input("Address (optional): ").strip() or None
    try:
        cid = create_customer(name, dob, nid, phone, email, address)
        print(f"\n  ✓ Customer created. CustomerID = {cid}\n")
    except Exception as e:
        print(f"\n  ✗ {_clean_error(e)}\n")


def menu_new_contract():
    print("\n── CREATE NEW CONTRACT ──")

    search = input("Search customer (name or NationalID): ").strip()
    customers = find_customer(search)
    if not customers:
        print("  No customers found.\n")
        return
    fmt(customers)
    cid = _input_int("Select CustomerID: ")

    print("\nAvailable regions:")
    fmt(get_regions())
    region_id   = _input_int("Select RegionID: ")
    destination = input("Destination name    : ").strip()
    departure   = _input_date("Departure date      : (YYYY-MM-DD) ")
    return_date = _input_date("Return date         : (YYYY-MM-DD) ")
    num_travelers = _input_int("Number of travelers : ")

    print("\nActive insurance plans:")
    fmt(get_plans())
    plan_id = _input_int("Select PlanID: ")

    # Preview premium BEFORE creating the trip — if user cancels,
    # no orphan Trip row is left in the database.
    # We need a temporary trip object for the UDF; we create it
    # only after the user confirms.
    premium_preview = None
    try:
        # Create trip first (needed by fn_CalculatePremium)
        trip_id = create_trip(destination, region_id, departure, return_date, num_travelers)
        premium_preview = preview_premium(plan_id, trip_id)
        print(f"\n  Estimated premium: {premium_preview:,.0f} VND")
    except Exception as e:
        print(f"  ✗ {_clean_error(e)}\n")
        return

    confirm = input("  Confirm and create contract? (y/n): ").strip().lower()
    if confirm != "y":
        # User cancelled — clean up the trip we already inserted
        try:
            with _cursor() as (_, cur):
                cur.execute("DELETE FROM Trips WHERE TripID = %s", (trip_id,))
        except Exception:
            pass  # Best-effort cleanup; trip has no contract yet so it's harmless
        print("  Cancelled.\n")
        return

    try:
        contract_id, premium = create_contract(cid, trip_id, plan_id)
        print(f"\n  ✓ Contract created. ContractID = {contract_id} | Premium = {premium:,.0f} VND\n")
    except Exception as e:
        print(f"\n  ✗ {_clean_error(e)}\n")


def menu_file_claim():
    print("\n── FILE A CLAIM ──")
    contract_id   = _input_int("ContractID: ")
    print("\nClaim types:")
    fmt(get_claim_types())
    claim_type_id = _input_int("Select ClaimTypeID: ")
    description   = input("Incident description: ").strip()

    try:
        claim_id = file_claim(contract_id, claim_type_id, description)
        print(f"\n  ✓ Claim filed. ClaimID = {claim_id} — Status: under_review\n")
    except Exception as e:
        print(f"\n  ✗ {_clean_error(e)}\n")


def menu_process_assessment():
    print("\n── PROCESS ASSESSMENT ──")
    pending = get_pending_claims()
    if not pending:
        print("  No pending claims to assess.\n")
        return
    print("Pending / under-review claims:")
    fmt(pending)

    claim_id = _input_int("ClaimID to assess: ")

    # Validate result input
    while True:
        result = input("Decision (approved / rejected): ").strip().lower()
        if result in ("approved", "rejected"):
            break
        print("  ✗ Please type 'approved' or 'rejected'.")

    if result == "approved":
        amount = _input_decimal("Approved amount (VND): ")
    else:
        amount = Decimal("0")
        print("  Amount set to 0 for rejected claims.")

    note = input("Assessor note: ").strip()

    # Confirmation — assessment is irreversible
    print(f"\n  Decision  : {result.upper()}")
    print(f"  Amount    : {amount:,.0f} VND")
    confirm = input("  Confirm? This cannot be undone. (y/n): ").strip().lower()
    if confirm != "y":
        print("  Cancelled.\n")
        return

    try:
        process_assessment(claim_id, result, amount, note)
        print(f"\n  ✓ Assessment recorded.")
        if result == "approved":
            print("  Trigger auto-created a Payout record.\n")
        detail = get_claim_detail(claim_id)
        if detail:
            fmt([detail])
    except Exception as e:
        print(f"\n  ✗ {_clean_error(e)}\n")


def menu_reports():
    print("\n── REPORTS ──")
    print("  1. Monthly payout summary")
    print("  2. Contract claim summary (with success rate)")
    print("  3. Claim approval rate by type")
    print("  4. Upcoming contract expiries (next 30 days)")
    choice = input("Select: ").strip()

    if choice == "1":
        fmt(report_monthly_payouts())
    elif choice == "2":
        fmt(report_contract_claim_summary())
    elif choice == "3":
        fmt(report_success_rate_by_claim_type())
    elif choice == "4":
        fmt(report_upcoming_expiries())
    else:
        print("  Invalid choice.\n")


def main():
    print("\n╔══════════════════════════════════════════╗")
    print("║  TripAssure Travel Insurance  v1.0      ║")
    print("╚══════════════════════════════════════════╝\n")

    MENU = {
        "1": ("View active contracts",   lambda: fmt(get_active_contracts())),
        "2": ("Enroll new customer",     menu_enroll),
        "3": ("Create new contract",     menu_new_contract),
        "4": ("File a claim",            menu_file_claim),
        "5": ("Process assessment",      menu_process_assessment),
        "6": ("View pending claims",     lambda: fmt(get_pending_claims())),
        "7": ("Reports",                 menu_reports),
        "0": ("Exit",                    None),
    }

    while True:
        print("─" * 44)
        for key, (label, _) in MENU.items():
            print(f"  {key}. {label}")
        print("─" * 44)

        choice = input("Select: ").strip()
        if choice == "0":
            print("\n  Goodbye.\n")
            break
        if choice in MENU:
            _, fn = MENU[choice]
            try:
                fn()
            except Exception as e:
                print(f"\n  Unexpected error: {_clean_error(e)}\n")
        else:
            print("  Invalid option.\n")


if __name__ == "__main__":
    main()