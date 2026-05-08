"""
TripAssure Travel Insurance — Streamlit Dashboard
Run:  streamlit run web.py
Req:  pip install streamlit mysql-connector-python plotly
"""

import streamlit as st
import pandas as pd
import plotly.express as px
import plotly.graph_objects as go
from decimal import Decimal
import datetime

from app import (
    create_customer, find_customer,
    get_plans, get_regions, create_trip, create_contract,
    get_active_contracts,
    get_claim_types, file_claim, get_pending_claims,
    process_assessment, get_claim_detail,
    report_monthly_payouts, report_contract_claim_summary,
    report_success_rate_by_claim_type, report_upcoming_expiries,
    _clean_error,
)

# ─────────────────────────────────────────────────────────────────────────────
# PAGE CONFIG
# ─────────────────────────────────────────────────────────────────────────────
st.set_page_config(
    page_title="TripAssure Insurance",
    page_icon="🛡️",
    layout="wide",
    initial_sidebar_state="expanded",
)

# ─────────────────────────────────────────────────────────────────────────────
# GLOBAL CSS  —  light, clean, airy
# ─────────────────────────────────────────────────────────────────────────────
st.markdown("""
<style>
@import url('https://fonts.googleapis.com/css2?family=DM+Sans:ital,opsz,wght@0,9..40,300;0,9..40,400;0,9..40,500;0,9..40,600;1,9..40,400&display=swap');

/* ── Base ── */
html, body, [class*="css"] {
    font-family: 'DM Sans', sans-serif !important;
    background: #ffffff !important;
    color: #18181b !important;
}
#MainMenu { visibility: hidden; }
footer { visibility: hidden; }
header { background-color: transparent !important; }

/* ── Luôn hiện nút collapse/expand sidebar ── */
[data-testid="collapsedControl"] {
    display: block !important;
    visibility: visible !important;
    opacity: 1 !important;
}

/* ── Content area — reduce top gap ── */
.main .block-container {
    padding-top: 0.5rem !important;
    padding-bottom: 3rem !important;
    padding-left: 2.5rem !important;
    padding-right: 2.5rem !important;
    max-width: 1160px;
    background: #ffffff !important;
}

/* ── Sidebar ── */
[data-testid="stSidebar"] {
    background: #fafafa !important;
    border-right: 1px solid #f0f0f0 !important;
}
[data-testid="stSidebarContent"] {
    padding: 1.25rem 0.9rem !important;
}
[data-testid="stSidebar"] .stButton > button {
    background: transparent !important;
    color: #52525b !important;
    border: none !important;
    border-radius: 6px !important;
    font-size: 0.84rem !important;
    font-weight: 400 !important;
    text-align: left !important;
    padding: 0.42rem 0.7rem !important;
    margin-bottom: 1px;
    width: 100%;
    transition: background 0.12s, color 0.12s;
}
[data-testid="stSidebar"] .stButton > button:hover {
    background: #f0f0f0 !important;
    color: #18181b !important;
}

/* ── Headings ── */
h1 {
    font-size: 1.45rem !important;
    font-weight: 600 !important;
    color: #18181b !important;
    letter-spacing: -0.01em !important;
    margin-bottom: 0.15rem !important;
    line-height: 1.25 !important;
}
h2 {
    font-size: 0.78rem !important;
    font-weight: 600 !important;
    color: #71717a !important;
    letter-spacing: 0.07em !important;
    text-transform: uppercase !important;
    margin: 1.6rem 0 0.65rem !important;
}
h3 {
    font-size: 0.9rem !important;
    font-weight: 500 !important;
    color: #3f3f46 !important;
    margin: 0.8rem 0 0.4rem !important;
}

/* ── Metric cards ── */
[data-testid="stMetric"] {
    background: #ffffff !important;
    border: 1px solid #e4e4e7 !important;
    border-radius: 10px !important;
    padding: 1rem 1.2rem !important;
    box-shadow: none !important;
}
[data-testid="stMetricLabel"] {
    font-size: 0.72rem !important;
    font-weight: 500 !important;
    letter-spacing: 0.05em !important;
    text-transform: uppercase !important;
    color: #a1a1aa !important;
}
[data-testid="stMetricValue"] {
    font-size: 1.5rem !important;
    font-weight: 600 !important;
    color: #18181b !important;
    letter-spacing: -0.02em !important;
}
[data-testid="stMetricDelta"] { font-size: 0.74rem !important; }

/* ── Dataframe ── */
[data-testid="stDataFrame"] {
    border: 1px solid #e4e4e7 !important;
    border-radius: 10px !important;
    overflow: hidden !important;
}
iframe[title="st_aggrid_base"] { border-radius: 10px !important; }

/* ── Forms ── */
[data-testid="stForm"] {
    background: #ffffff !important;
    border: 1px solid #e4e4e7 !important;
    border-radius: 12px !important;
    padding: 1.5rem 1.75rem 1.75rem !important;
    box-shadow: none !important;
}

/* ── Input fields ── */
.stTextInput > div > div > input,
.stTextArea > div > div > textarea,
.stNumberInput > div > div > input {
    background: #ffffff !important;
    border: 1px solid #d4d4d8 !important;
    border-radius: 7px !important;
    font-size: 0.87rem !important;
    color: #18181b !important;
    padding: 0.42rem 0.7rem !important;
}
.stTextInput > div > div > input:focus,
.stTextArea > div > div > textarea:focus,
.stNumberInput > div > div > input:focus {
    border-color: #71717a !important;
    box-shadow: none !important;
}
/* Field labels */
.stTextInput > label, .stTextArea > label,
.stNumberInput > label, .stSelectbox > label,
.stDateInput > label, .stRadio > label,
.stSlider > label {
    font-size: 0.78rem !important;
    font-weight: 500 !important;
    color: #52525b !important;
    letter-spacing: 0.01em !important;
}

/* ── Primary buttons (non-form) ── */
.main .stButton > button {
    background: #18181b !important;
    color: #ffffff !important;
    border: none !important;
    border-radius: 7px !important;
    font-size: 0.84rem !important;
    font-weight: 500 !important;
    padding: 0.5rem 1.1rem !important;
    transition: opacity 0.15s;
}
.main .stButton > button:hover { opacity: 0.78 !important; }

/* ── Form submit button ── */
[data-testid="stFormSubmitButton"] > button {
    background: #18181b !important;
    color: #ffffff !important;
    border: none !important;
    border-radius: 7px !important;
    font-size: 0.84rem !important;
    font-weight: 500 !important;
    padding: 0.5rem 1.1rem !important;
    transition: opacity 0.15s;
}
[data-testid="stFormSubmitButton"] > button:hover { opacity: 0.78 !important; }

/* ── Tabs ── */
.stTabs [data-baseweb="tab-list"] {
    background: transparent !important;
    border-bottom: 1px solid #e4e4e7 !important;
    gap: 0 !important;
    padding-bottom: 0 !important;
}
.stTabs [data-baseweb="tab"] {
    background: transparent !important;
    border: none !important;
    border-bottom: 2px solid transparent !important;
    border-radius: 0 !important;
    color: #a1a1aa !important;
    font-size: 0.84rem !important;
    font-weight: 400 !important;
    padding: 0.5rem 1rem !important;
    margin-bottom: -1px;
}
.stTabs [aria-selected="true"] {
    color: #18181b !important;
    border-bottom: 2px solid #3b82f6 !important;
    font-weight: 500 !important;
}

/* ── Alerts ── */
[data-testid="stAlert"] {
    border-radius: 8px !important;
    font-size: 0.84rem !important;
    border-left-width: 3px !important;
}

/* ── Select / radio / slider ── */
.stSelectbox > div > div {
    background: #ffffff !important;
    border: 1px solid #d4d4d8 !important;
    border-radius: 7px !important;
    font-size: 0.87rem !important;
}
.stRadio > div { gap: 0.5rem !important; }
.stRadio [data-testid="stMarkdownContainer"] p {
    font-size: 0.87rem !important;
    color: #3f3f46 !important;
}

/* ── Divider ── */
hr {
    border: none !important;
    border-top: 1px solid #f0f0f0 !important;
    margin: 1rem 0 !important;
}

/* ── Caption ── */
.stCaption, [data-testid="stCaptionContainer"] p {
    font-size: 0.76rem !important;
    color: #a1a1aa !important;
}

/* ── Custom inline tags ── */
.tag {
    display: inline-block;
    padding: 0.18rem 0.55rem;
    border-radius: 4px;
    font-size: 0.72rem;
    font-weight: 500;
    letter-spacing: 0.02em;
    line-height: 1.6;
}
.tag-blue  { background: #eff6ff; color: #1d4ed8; }
.tag-green { background: #f0fdf4; color: #15803d; }
.tag-red   { background: #fef2f2; color: #b91c1c; }
.tag-gray  { background: #f4f4f5; color: #52525b; }
.tag-amber { background: #fffbeb; color: #b45309; }

/* ── Info strip ── */
.strip {
    background: #fafafa;
    border: 1px solid #e4e4e7;
    border-radius: 8px;
    padding: 0.7rem 1rem;
    font-size: 0.83rem;
    color: #3f3f46;
    line-height: 1.65;
    margin: 0.4rem 0;
}
.strip-blue {
    background: #eff6ff;
    border: 1px solid #bfdbfe;
    border-left: 3px solid #3b82f6;
    border-radius: 0 8px 8px 0;
    padding: 0.7rem 1rem;
    font-size: 0.83rem;
    color: #1e40af;
    line-height: 1.65;
    margin: 0.4rem 0;
}
.strip-amber {
    background: #fffbeb;
    border: 1px solid #fde68a;
    border-left: 3px solid #f59e0b;
    border-radius: 0 8px 8px 0;
    padding: 0.7rem 1rem;
    font-size: 0.83rem;
    color: #92400e;
    line-height: 1.65;
    margin: 0.4rem 0;
}

/* ── Page subtitle ── */
.sub {
    font-size: 0.82rem;
    color: #a1a1aa;
    margin: -0.1rem 0 1.4rem;
    font-weight: 400;
}
</style>
""", unsafe_allow_html=True)


# ─────────────────────────────────────────────────────────────────────────────
# HELPERS
# ─────────────────────────────────────────────────────────────────────────────
def vnd(x):
    if x is None: return "—"
    try:    return f"{int(x):,} ₫"
    except: return str(x)

def to_df(rows):
    return pd.DataFrame(rows) if rows else pd.DataFrame()

# ── Color palette ──────────────────────────────────────────────────────────
# Defined once, used everywhere — semantic, not decorative.
#   BLUE   primary data / bars / financial values
#   GREEN  approved / positive / success
#   AMBER  pending / warning / expiring soon
#   ROSE   rejected / danger
#   GRAY   neutral / secondary series
C_BLUE  = "#3b82f6"
C_GREEN = "#10b981"
C_AMBER = "#f59e0b"
C_ROSE  = "#f43f5e"
C_GRAY  = "#a1a1aa"
C_INK   = "#18181b"

# Multi-series palette for claim type charts (5 types max)
CLAIM_COLORS = [C_BLUE, C_AMBER, C_GREEN, C_ROSE, "#8b5cf6"]

# Shared Plotly layout — minimal frame, no chrome
PLOT_LAYOUT = dict(
    font=dict(family="DM Sans", size=11, color="#52525b"),
    paper_bgcolor="rgba(0,0,0,0)",
    plot_bgcolor="rgba(0,0,0,0)",
    margin=dict(t=36, l=0, r=0, b=0),
    showlegend=True,
    legend=dict(font=dict(size=11), bgcolor="rgba(0,0,0,0)"),
    xaxis=dict(showgrid=False, linecolor="#e4e4e7", tickfont=dict(size=10)),
    yaxis=dict(gridcolor="#f4f4f5", linecolor="rgba(0,0,0,0)",
               tickfont=dict(size=10), rangemode="tozero"),
)


def apply_layout(fig, **kwargs):
    layout = {**PLOT_LAYOUT, **kwargs}
    fig.update_layout(**layout)
    return fig


# ─────────────────────────────────────────────────────────────────────────────
# SESSION STATE
# ─────────────────────────────────────────────────────────────────────────────
for k, v in [("role", None), ("page", None), ("db_user", None)]:
    if k not in st.session_state:
        st.session_state[k] = v

# Map UI role → DB credentials
# Mỗi role dùng đúng DB user của mình — RBAC được enforce tại tầng DB
ROLE_DB_CREDENTIALS = {
    "agent":    {"user": "tripAssure_agent",    "password": "AgentPass@2025"},
    "assessor": {"user": "tripAssure_assessor", "password": "AssessorPass@2025"},
    "admin":    {"user": "tripAssure_admin",     "password": "AdminPass@2025"},
}


# ─────────────────────────────────────────────────────────────────────────────
# LOGIN
# ─────────────────────────────────────────────────────────────────────────────
def page_login():
    _, col, _ = st.columns([1, 1.4, 1])
    with col:
        st.markdown("""
        <div style="text-align:center; margin-bottom:2rem;">
            <div style="font-size:2rem; margin-bottom:0.5rem;">🛡️</div>
            <div style="font-size:1.3rem; font-weight:600; color:#18181b; letter-spacing:-0.01em;">
                TripAssure Insurance
            </div>
            <div style="font-size:0.82rem; color:#a1a1aa; margin-top:4px;">
                Travel Insurance Management System
            </div>
        </div>
        """, unsafe_allow_html=True)

        with st.form("login_form"):
            role = st.radio(
                "Sign in as",
                ["Agent", "Assessor", "Admin"],
                horizontal=True,
            )
            st.markdown("""<div style="font-size:0.76rem; color:#a1a1aa; margin: 0.25rem 0 0.5rem;">
                <b style="color:#52525b">Agent</b> — contracts & claims &nbsp;·&nbsp;
                <b style="color:#52525b">Assessor</b> — claim decisions &nbsp;·&nbsp;
                <b style="color:#52525b">Admin</b> — reports & overview
            </div>""", unsafe_allow_html=True)
            submitted = st.form_submit_button("Continue →", width="stretch")

        if submitted:
            role_key = role.lower()
            creds    = ROLE_DB_CREDENTIALS[role_key]
            # Ghi DB credentials vào session — app.get_connection() sẽ đọc từ đây
            st.session_state.role    = role_key
            st.session_state.db_user = creds["user"]
            # Lưu password trong session state (in-memory, không persist sang disk)
            st.session_state.db_pass = creds["password"]
            st.session_state.page    = None
            st.rerun()


# ─────────────────────────────────────────────────────────────────────────────
# SIDEBAR NAV
# ─────────────────────────────────────────────────────────────────────────────
MENUS = {
    "agent": {
        "label": "Agent",
        "pages": [
            ("Active Contracts",    "active_contracts"),
            ("Enroll Customer",    "enroll"),
            ("Create Contract",    "new_contract"),
            ("File a Claim",       "file_claim"),
        ],
    },
    "assessor": {
        "label": "Assessor",
        "pages": [
            ("Claim Queue",        "pending_claims"),
            ("Process Assessment", "process_assessment"),
        ],
    },
    "admin": {
        "label": "Admin",
        "pages": [
            ("Dashboard",          "dashboard"),
            ("Monthly Payouts",    "monthly_payouts"),
            ("Contract Summary",   "contract_summary"),
            ("Claim Type Stats",   "claim_type_report"),
            ("Expiring Soon",      "expiries"),
        ],
    },
}

def render_sidebar():
    role = st.session_state.role
    cfg  = MENUS[role]
    with st.sidebar:
        st.markdown(f"""
        <div style="padding: 0.25rem 0 0.75rem 0.2rem;">
            <div style="font-size:0.7rem; font-weight:600; letter-spacing:0.08em;
                        text-transform:uppercase; color:#a1a1aa; margin-bottom:0.15rem;">
                {cfg['label']}
            </div>
            <div style="font-size:0.82rem; font-weight:500; color:#18181b;">TripAssure Insurance</div>
        </div>
        """, unsafe_allow_html=True)
        st.divider()

        for label, key in cfg["pages"]:
            if st.button(label, key=f"nav_{key}", width="stretch"):
                st.session_state.page = key
                st.rerun()

        st.divider()

        # Xóa tham số icon đi, chèn thẳng ký tự vào chuỗi text
        if st.button("⎋ Log out", width="stretch"):
            st.session_state.role = None
            st.session_state.page = None
            st.rerun()

# ─────────────────────────────────────────────────────────────────────────────
# AGENT — Active Contracts
# ─────────────────────────────────────────────────────────────────────────────
def page_active_contracts():
    st.title("Active Contracts")
    st.markdown('<p class="sub">All contracts currently in active status.</p>', unsafe_allow_html=True)
    try:
        data = get_active_contracts()
        if not data:
            st.info("No active contracts found.")
            return
        df = to_df(data)
        if "TotalPremium" in df.columns:
            df["TotalPremium"] = df["TotalPremium"].apply(vnd)
        st.dataframe(df, width="stretch", hide_index=True)
        st.caption(f"{len(data)} contract(s)")
    except Exception as e:
        st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# AGENT — Enroll Customer
# ─────────────────────────────────────────────────────────────────────────────
def page_enroll():
    st.title("Enroll New Customer")
    st.markdown('<p class="sub">Register a new customer in the system.</p>', unsafe_allow_html=True)

    with st.form("enroll_form"):
        c1, c2 = st.columns(2)
        with c1:
            name    = st.text_input("Full name *")
            dob     = st.date_input("Date of birth *",
                                    min_value=datetime.date(1924, 1, 1),
                                    max_value=datetime.date.today())
            nid     = st.text_input("National ID *")
        with c2:
            phone   = st.text_input("Phone *")
            email   = st.text_input("Email")
            address = st.text_area("Address", height=95)

        submitted = st.form_submit_button("Create customer", width="stretch")

    if submitted:
        if not (name.strip() and nid.strip() and phone.strip()):
            st.error("Please fill in all required fields.")
        else:
            try:
                cid = create_customer(
                    name.strip(), str(dob), nid.strip(), phone.strip(),
                    email.strip() or None, address.strip() or None,
                )
                st.success(f"Customer created — ID **{cid}**")
            except Exception as e:
                st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# AGENT — Create Contract
# ─────────────────────────────────────────────────────────────────────────────
def page_new_contract():
    st.title("Create New Contract")
    st.markdown('<p class="sub">Find a customer, enter trip details, and issue a contract.</p>',
                unsafe_allow_html=True)

    # ── Step 1: Customer search ──
    st.markdown("## Step 1 — Customer")
    search = st.text_input("Search by name or National ID", placeholder="e.g. Nguyen Van An")

    customer_id = None
    if search.strip():
        try:
            results = find_customer(search.strip())
            if not results:
                st.warning("No customers found.")
            else:
                st.dataframe(to_df(results), width="stretch", hide_index=True)
                customer_id = st.selectbox(
                    "Select customer ID",
                    [r["CustomerID"] for r in results],
                    format_func=lambda cid: f"ID {cid} — {next(r['FullName'] for r in results if r['CustomerID']==cid)}",
                )
        except Exception as e:
            st.error(_clean_error(e))
            return
    else:
        st.caption("Enter a name or National ID above to search.")

    # ── Step 2: Trip + Plan ──
    st.markdown("## Step 2 — Trip & Plan")
    try:
        regions = get_regions()
        plans   = get_plans()
    except Exception as e:
        st.error(_clean_error(e))
        return

    region_map = {r["RegionName"]: r for r in regions}
    plan_map   = {p["PlanName"]:   p for p in plans if p["IsActive"]}

    # Đưa phần chọn Plan và hiển thị giá ra NGOÀI form
    plan_name = st.selectbox("Insurance plan *", list(plan_map.keys()))
    sel_plan  = plan_map.get(plan_name)
    if sel_plan:
        st.markdown(f"""<div class="strip">
            {int(sel_plan['BasePremiumPerPersonPerDay']):,} ₫ / person / day &nbsp;·&nbsp;
            Max {sel_plan['MaxClaimsPerYear']} claims / year
        </div>""", unsafe_allow_html=True)

    # Đưa các trường nhập liệu text/date vào TRONG form
    with st.form("contract_form"):
        c1, c2 = st.columns(2)
        with c1:
            destination   = st.text_input("Destination *", placeholder="e.g. Tokyo, Japan")
            region_name   = st.selectbox("Region *", list(region_map.keys()))
            departure     = st.date_input("Departure *", min_value=datetime.date.today())
            return_date   = st.date_input(
                "Return *",
                min_value=datetime.date.today() + datetime.timedelta(days=1),
            )
        with c2:
            num_travelers = st.number_input("Travelers *", min_value=1, max_value=50, value=1)

        submitted = st.form_submit_button("Calculate & create contract", width="stretch")

    if submitted:
        if not customer_id:
            st.error("Select a customer first.")
            return
        if not destination.strip():
            st.error("Enter a destination.")
            return
        if return_date <= departure:
            st.error("Return date must be after departure date.")
            return
        try:
            sel_region = region_map[region_name]
            sel_plan   = plan_map[plan_name] # Vẫn lấy được biến từ bên ngoài form
            days       = (return_date - departure).days

            premium_est = (
                float(sel_plan["BasePremiumPerPersonPerDay"])
                * num_travelers * days
                * float(sel_region["PremiumMultiplier"])
            )

            c1, c2, c3 = st.columns(3)
            c1.metric("Duration", f"{days} days")
            c2.metric("Travelers", num_travelers)
            c3.metric("Premium", vnd(premium_est))

            trip_id = create_trip(
                destination, sel_region["RegionID"],
                str(departure), str(return_date), num_travelers,
            )
            contract_id, total = create_contract(customer_id, trip_id, sel_plan["PlanID"])
            st.success(
                f"Contract created — ID **{contract_id}** · Premium locked at **{vnd(total)}**"
            )
        except Exception as e:
            st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# AGENT — File a Claim
# ─────────────────────────────────────────────────────────────────────────────
def page_file_claim():
    st.title("File a Claim")
    st.markdown('<p class="sub">Submit a compensation request against an active contract.</p>',
                unsafe_allow_html=True)
    try:
        claim_types = get_claim_types()
    except Exception as e:
        st.error(_clean_error(e))
        return

    type_map = {ct["TypeName"]: ct for ct in claim_types}

    # Đưa phần chọn Claim Type ra NGOÀI form
    type_name = st.selectbox("Claim type *", list(type_map.keys()))
    sel       = type_map.get(type_name)
    if sel:
        st.markdown(f"""<div class="strip-blue">
            Covers <b>{sel['CoveragePercentage']}%</b> of the loss &nbsp;·&nbsp;
            Max payout <b>{vnd(sel['MaxCoverageAmount'])}</b>
        </div>""", unsafe_allow_html=True)

    # Đưa các trường cần gõ tay vào TRONG form
    with st.form("claim_form"):
        contract_id = st.number_input("Contract ID *", min_value=1, step=1)
        description = st.text_area(
            "Incident description *", height=120,
            placeholder="What happened, when and where — include any reference numbers.",
        )
        submitted = st.form_submit_button("Submit claim", width="stretch")

    if submitted:
        if not description.strip():
            st.error("Please describe the incident.")
        else:
            try:
                cid = file_claim(int(contract_id), sel["ClaimTypeID"], description.strip())
                st.success(f"Claim submitted — ID **{cid}** · Status: under review")
            except Exception as e:
                st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# ASSESSOR — Claim Queue
# ─────────────────────────────────────────────────────────────────────────────
def page_pending_claims():
    st.title("Claim Queue")
    st.markdown('<p class="sub">All claims pending or under review — oldest first.</p>',
                unsafe_allow_html=True)
    try:
        data = get_pending_claims()
        if not data:
            st.success("No claims awaiting review.")
            return
        df = to_df(data)
        if "MaxCoverageAmount" in df.columns:
            df["MaxCoverageAmount"] = df["MaxCoverageAmount"].apply(vnd)
        st.dataframe(df, width="stretch", hide_index=True)
        st.caption(f"{len(data)} claim(s) pending")
    except Exception as e:
        st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# ASSESSOR — Process Assessment
# ─────────────────────────────────────────────────────────────────────────────
def page_process_assessment():
    st.title("Process Assessment")
    st.markdown('<p class="sub">Review a claim and record your decision.</p>',
                unsafe_allow_html=True)
    try:
        pending = get_pending_claims()
    except Exception as e:
        st.error(_clean_error(e))
        return

    if not pending:
        st.success("No claims to assess right now.")
        return

    # Đưa Selectbox và thẻ thông tin tóm tắt ra NGOÀI form
    claim_id = st.selectbox(
        "Select claim",
        [p["ClaimID"] for p in pending],
        format_func=lambda cid: f"#{cid} — {next(p['CustomerName'] for p in pending if p['ClaimID']==cid)}",
    )
    sel = next((p for p in pending if p["ClaimID"] == claim_id), None)
    if sel:
        st.markdown(f"""<div class="strip-amber">
            <b>{sel['ClaimType']}</b> &nbsp;·&nbsp; Filed {sel['FilingDate']}
            &nbsp;·&nbsp; Max {vnd(sel['MaxCoverageAmount'])} ({sel['CoveragePercentage']}% coverage)<br>
            <span style="opacity:0.85">{sel['IncidentDescription']}</span>
        </div>""", unsafe_allow_html=True)

    st.divider()

    # Khối form chỉ chứa các thao tác ghi nhận quyết định
    with st.form("assessment_form"):
        result = st.radio("Decision *", ["approved", "rejected"], horizontal=True)
        amount = Decimal("0")
        if result == "approved":
            raw    = st.number_input("Approved amount (VND) *", min_value=0, step=100_000)
            amount = Decimal(str(raw))
        note = st.text_area(
            "Assessor note *", height=100,
            placeholder="Summarize evidence reviewed and the reason for your decision.",
        )
        submitted = st.form_submit_button(
            "Confirm decision — this cannot be undone", width="stretch"
        )

    if submitted:
        if not note.strip():
            st.error("Add an assessor note before confirming.")
        else:
            try:
                process_assessment(claim_id, result, amount, note.strip())
                if result == "approved":
                    st.success(
                        f"Claim **#{claim_id}** approved — {vnd(amount)}\n\n"
                        "Payout record created automatically by the database."
                    )
                else:
                    st.warning(f"Claim **#{claim_id}** rejected.")
                detail = get_claim_detail(claim_id)
                if detail:
                    st.markdown("#### Claim record")
                    df_d = pd.DataFrame([{"Field": k, "Value": str(v)} for k, v in detail.items()])
                    st.dataframe(df_d, width="stretch", hide_index=True)
            except Exception as e:
                st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN — Dashboard
# ─────────────────────────────────────────────────────────────────────────────
def page_dashboard():
    st.title("Dashboard")
    st.markdown('<p class="sub">Current portfolio snapshot.</p>', unsafe_allow_html=True)

    try:
        active  = get_active_contracts()
        pending = get_pending_claims()
        summary = report_contract_claim_summary()
        monthly = report_monthly_payouts()
        by_type = report_success_rate_by_claim_type()
    except Exception as e:
        st.error(_clean_error(e))
        return

    total_premium = sum(float(r["TotalPremium"])    for r in summary) if summary else 0
    total_payout  = sum(float(r["TotalPaidOutVND"]) for r in summary) if summary else 0

    # KPIs
    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Active contracts",  len(active))
    c2.metric("Pending claims",    len(pending))
    c3.metric("Premium collected", vnd(total_premium))
    c4.metric("Total paid out",    vnd(total_payout))

    # Amber nudge when there are pending claims waiting
    if len(pending) > 0:
        st.markdown(
            f'<div class="strip-amber" style="margin-bottom:0.5rem;">'
            f'⚠ &nbsp;<b>{len(pending)} claim(s)</b> are waiting for assessment.</div>',
            unsafe_allow_html=True,
        )

    st.markdown("## Charts")
    col_l, col_r = st.columns(2)

    # Monthly payouts bar — blue bars, gray avg line
    with col_l:
        if monthly:
            df_m = to_df(monthly)
            df_m["Month"] = (df_m["PayoutYear"].astype(str) + "-"
                             + df_m["PayoutMonth"].astype(str).str.zfill(2))
            fig = go.Figure()
            fig.add_trace(go.Bar(
                x=df_m["Month"], y=df_m["TotalAmountVND"], name="Total payout",
                marker_color=C_BLUE, marker_line_width=0,
            ))
            fig.add_trace(go.Scatter(
                x=df_m["Month"], y=df_m["AvgAmountVND"], name="Avg per payout",
                mode="lines+markers",
                line=dict(color=C_GRAY, width=1.5, dash="dot"),
                marker=dict(size=5, color=C_GRAY),
            ))
            apply_layout(fig, title=dict(text="Monthly payouts (VND)", font=dict(size=12, color="#52525b")))
            st.plotly_chart(fig, width="stretch")
        else:
            st.info("No payout data yet.")

    # Claims by type donut — semantic CLAIM_COLORS
    with col_r:
        if by_type:
            df_t = to_df(by_type)
            df_t = df_t[df_t["TotalClaims"] > 0]
            fig2 = go.Figure(go.Pie(
                labels=df_t["TypeName"], values=df_t["TotalClaims"],
                hole=0.55,
                marker=dict(colors=CLAIM_COLORS[:len(df_t)]),
                textfont=dict(size=10),
                hovertemplate="<b>%{label}</b><br>%{value} claims (%{percent})<extra></extra>",
            ))
            apply_layout(fig2, title=dict(text="Claims by type", font=dict(size=12, color="#52525b")),
                         showlegend=True,
                         legend=dict(font=dict(size=10), bgcolor="rgba(0,0,0,0)", orientation="v"))
            st.plotly_chart(fig2, width="stretch")
        else:
            st.info("No claim data yet.")

    # Approved vs Rejected stacked — green/rose, clearly semantic
    if by_type:
        df_t2 = to_df(by_type)
        fig3 = go.Figure()
        fig3.add_trace(go.Bar(
            name="Approved", x=df_t2["TypeName"], y=df_t2["Approved"],
            marker_color=C_GREEN, marker_line_width=0,
        ))
        fig3.add_trace(go.Bar(
            name="Rejected", x=df_t2["TypeName"], y=df_t2["Rejected"],
            marker_color=C_ROSE, marker_line_width=0,
        ))
        apply_layout(fig3,
                     title=dict(text="Approved vs. rejected by type", font=dict(size=12, color="#52525b")),
                     barmode="stack")
        st.plotly_chart(fig3, width="stretch")


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN — Monthly Payouts
# ─────────────────────────────────────────────────────────────────────────────
def page_monthly_payouts():
    st.title("Monthly Payout Summary")
    st.markdown('<p class="sub">Total payouts grouped by month.</p>', unsafe_allow_html=True)
    try:
        data = report_monthly_payouts()
        if not data:
            st.info("No payout records found.")
            return
        df = to_df(data)
        df["Month"] = (df["PayoutYear"].astype(str) + "-"
                       + df["PayoutMonth"].astype(str).str.zfill(2))
        fig = go.Figure()
        fig.add_trace(go.Bar(
            x=df["Month"], y=df["TotalAmountVND"], name="Total",
            marker_color=C_BLUE, marker_line_width=0,
        ))
        fig.add_trace(go.Scatter(
            x=df["Month"], y=df["AvgAmountVND"], name="Avg per payout",
            mode="lines+markers",
            line=dict(color=C_GRAY, width=1.5, dash="dot"),
            marker=dict(size=5, color=C_GRAY),
        ))
        apply_layout(fig,
                     title=dict(text="Monthly payout total + average (VND)", font=dict(size=12, color="#52525b")))
        st.plotly_chart(fig, width="stretch")

        df_show = df.drop(columns=["Month"]).copy()
        df_show["TotalAmountVND"] = df_show["TotalAmountVND"].apply(vnd)
        df_show["AvgAmountVND"]   = df_show["AvgAmountVND"].apply(vnd)
        st.dataframe(df_show, width="stretch", hide_index=True)
    except Exception as e:
        st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN — Contract Summary
# ─────────────────────────────────────────────────────────────────────────────
def page_contract_summary():
    st.title("Contract & Claim Summary")
    st.markdown('<p class="sub">Per-contract breakdown: premium, claims, payout, and approval rate.</p>',
                unsafe_allow_html=True)
    try:
        data = report_contract_claim_summary()
        if not data:
            st.info("No contracts found.")
            return
        df = to_df(data)

        if "TotalPremium" in df.columns and "TotalPaidOutVND" in df.columns:
            fig = go.Figure(go.Scatter(
                x=df["TotalPremium"].astype(float),
                y=df["TotalPaidOutVND"].astype(float),
                mode="markers",
                text=df["CustomerName"],
                marker=dict(
                    size=df["TotalClaims"].apply(lambda v: max(10, v * 7)).tolist(),
                    color=df["SuccessRatePct"].astype(float),
                    colorscale=[[0, "#fecdd3"], [0.5, C_BLUE], [1, C_GREEN]],
                    showscale=True,
                    colorbar=dict(title="Approval %", thickness=10, len=0.6,
                                  tickfont=dict(size=10)),
                    line=dict(width=0),
                    opacity=0.85,
                ),
                hovertemplate="<b>%{text}</b><br>Premium: %{x:,.0f} ₫<br>Paid out: %{y:,.0f} ₫<extra></extra>",
            ))
            apply_layout(fig,
                         title=dict(text="Premium collected vs. paid out  (bubble = claim count)", font=dict(size=12, color="#52525b")),
                         xaxis=dict(showgrid=False, linecolor="#e4e4e7", tickfont=dict(size=10), title="Premium (VND)"),
                         yaxis=dict(gridcolor="#f4f4f5", linecolor="rgba(0,0,0,0)", tickfont=dict(size=10), rangemode="tozero", title="Paid out (VND)"),
                         )
            st.plotly_chart(fig, width="stretch")

        df_show = df.copy()
        df_show["TotalPremium"]    = df_show["TotalPremium"].apply(vnd)
        df_show["TotalPaidOutVND"] = df_show["TotalPaidOutVND"].apply(vnd)
        st.dataframe(df_show, width="stretch", hide_index=True)
    except Exception as e:
        st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN — Claim Type Stats
# ─────────────────────────────────────────────────────────────────────────────
def page_claim_type_report():
    st.title("Claim Type Statistics")
    st.markdown('<p class="sub">Volume, approval rate, and payout by claim type.</p>',
                unsafe_allow_html=True)
    try:
        data = report_success_rate_by_claim_type()
        if not data:
            st.info("No claim data found.")
            return
        df = to_df(data)

        c_l, c_r = st.columns(2)
        with c_l:
            fig1 = go.Figure(go.Bar(
                x=df["TypeName"], y=df["ApprovalRatePct"],
                marker=dict(
                    color=df["ApprovalRatePct"].astype(float),
                    colorscale=[[0, "#fecdd3"], [0.5, C_BLUE], [1, C_GREEN]],
                    line=dict(width=0),
                ),
                text=df["ApprovalRatePct"].apply(lambda v: f"{v}%"),
                textposition="outside", textfont=dict(size=10),
            ))
            apply_layout(fig1,
                         title=dict(text="Approval rate by type (%)", font=dict(size=12, color="#52525b")),
                         yaxis=dict(gridcolor="#f4f4f5", linecolor="rgba(0,0,0,0)",
                                    tickfont=dict(size=10), range=[0, 115]),
                         showlegend=False)
            st.plotly_chart(fig1, width="stretch")

        with c_r:
            fig2 = go.Figure(go.Bar(
                x=df["TypeName"], y=df["TotalPaidOutVND"].astype(float),
                marker_color=C_AMBER, marker_line_width=0,
            ))
            apply_layout(fig2,
                         title=dict(text="Total paid out by type (VND)", font=dict(size=12, color="#52525b")),
                         showlegend=False)
            st.plotly_chart(fig2, width="stretch")

        df_show = df.copy()
        df_show["TotalPaidOutVND"] = df_show["TotalPaidOutVND"].apply(vnd)
        st.dataframe(df_show, width="stretch", hide_index=True)
    except Exception as e:
        st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# ADMIN — Expiring Soon
# ─────────────────────────────────────────────────────────────────────────────
def page_expiries():
    st.title("Expiring Soon")
    st.markdown('<p class="sub">Active contracts approaching their return date.</p>',
                unsafe_allow_html=True)
    days = st.slider("Show contracts expiring within (days)", 7, 90, 30)
    try:
        data = report_upcoming_expiries(days)
        if not data:
            st.success(f"No contracts expiring within {days} days.")
            return
        df = to_df(data)
        st.dataframe(df, width="stretch", hide_index=True)
        st.caption(f"{len(data)} contract(s)")

        if "DaysUntilExpiry" in df.columns and "FullName" in df.columns:
            dfs = df.sort_values("DaysUntilExpiry")
            fig = go.Figure(go.Bar(
                x=dfs["DaysUntilExpiry"],
                y=dfs["FullName"],
                orientation="h",
                marker=dict(
                    color=dfs["DaysUntilExpiry"],
                    colorscale=[[0, C_ROSE], [0.4, C_AMBER], [1, C_GREEN]],
                    line=dict(width=0),
                ),
                hovertemplate="%{y}: %{x} days remaining<extra></extra>",
            ))
            apply_layout(fig,
                         title=dict(text="Days until expiry by customer", font=dict(size=12, color="#52525b")),
                         showlegend=False,
                         xaxis=dict(showgrid=False, linecolor="#e4e4e7", tickfont=dict(size=10),
                                    title="Days remaining", rangemode="tozero"),
                         yaxis=dict(gridcolor="rgba(0,0,0,0)", linecolor="rgba(0,0,0,0)",
                                    tickfont=dict(size=10)),
                         )
            st.plotly_chart(fig, width="stretch")
    except Exception as e:
        st.error(_clean_error(e))


# ─────────────────────────────────────────────────────────────────────────────
# ROUTER
# ─────────────────────────────────────────────────────────────────────────────
PAGE_MAP = {
    "active_contracts":   page_active_contracts,
    "enroll":             page_enroll,
    "new_contract":       page_new_contract,
    "file_claim":         page_file_claim,
    "pending_claims":     page_pending_claims,
    "process_assessment": page_process_assessment,
    "dashboard":          page_dashboard,
    "monthly_payouts":    page_monthly_payouts,
    "contract_summary":   page_contract_summary,
    "claim_type_report":  page_claim_type_report,
    "expiries":           page_expiries,
}
DEFAULTS = {
    "agent":    "active_contracts",
    "assessor": "pending_claims",
    "admin":    "dashboard",
}


def main():
    if not st.session_state.role:
        page_login()
        return
    render_sidebar()
    page_key = st.session_state.page or DEFAULTS[st.session_state.role]
    fn = PAGE_MAP.get(page_key)
    if fn:
        fn()
    else:
        st.error("Page not found.")


if __name__ == "__main__":
    main()