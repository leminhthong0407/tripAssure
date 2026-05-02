-- ============================================================
-- TRAVEL INSURANCE MANAGEMENT SYSTEM
-- schema.sql — Database & Table DDL
-- Project 19 | NEU College of Technology
--
-- IDEMPOTENT: Safe to run multiple times.
-- Drops and recreates the entire database on each run.
-- Run order: schema.sql → advanced_objects.sql → sample_data.sql → demo_script.sql
-- ============================================================

-- Drop and recreate database for a clean slate every run.
DROP DATABASE IF EXISTS TravelInsuranceDB;

CREATE DATABASE TravelInsuranceDB
  DEFAULT CHARACTER SET utf8mb4
  DEFAULT COLLATE utf8mb4_unicode_ci;

USE TravelInsuranceDB;

-- ============================================================
-- 1. DESTINATION REGIONS
-- Geographic risk zones with premium multipliers.
-- Extracted from Trips to satisfy 3NF:
--   Trips.RegionID → RegionName → PremiumMultiplier would be
--   a transitive dependency if stored inside Trips.
-- ============================================================
CREATE TABLE DestinationRegions (
    RegionID            INT             AUTO_INCREMENT PRIMARY KEY,
    RegionName          VARCHAR(100)    NOT NULL UNIQUE,
    PremiumMultiplier   DECIMAL(4, 2)   NOT NULL DEFAULT 1.00
                            CHECK (PremiumMultiplier > 0),
    Description         VARCHAR(255)
);

-- ============================================================
-- 2. CUSTOMERS
-- Core policyholder entity.
-- NationalID is an alternate (candidate) key — one person,
-- one profile, enforced at DB level.
-- NationalID stored as VARCHAR to preserve leading zeros.
-- ============================================================
CREATE TABLE Customers (
    CustomerID      INT             AUTO_INCREMENT PRIMARY KEY,
    FullName        VARCHAR(100)    NOT NULL,
    DateOfBirth     DATE            NOT NULL,
    NationalID      VARCHAR(20)     NOT NULL UNIQUE,
    Phone           VARCHAR(15)     NOT NULL,
    Email           VARCHAR(100),
    Address         TEXT
);

-- ============================================================
-- 3. INSURANCE PLANS
-- Product catalog. BasePremiumPerPersonPerDay is the base rate
-- before the destination risk multiplier is applied.
-- MaxClaimsPerYear is enforced by trg_before_claim_insert.
-- IsActive = FALSE retires a plan without breaking FK
-- references from historical contracts.
-- ============================================================
CREATE TABLE InsurancePlans (
    PlanID                      INT             AUTO_INCREMENT PRIMARY KEY,
    PlanName                    VARCHAR(100)    NOT NULL,
    Description                 TEXT,
    BasePremiumPerPersonPerDay  DECIMAL(10, 2)  NOT NULL
                                    CHECK (BasePremiumPerPersonPerDay > 0),
    MaxClaimsPerYear            INT             NOT NULL DEFAULT 2
                                    CHECK (MaxClaimsPerYear >= 1),
    IsActive                    BOOLEAN         NOT NULL DEFAULT TRUE
);

-- ============================================================
-- 4. TRIPS
-- The insured object. Has its own lifecycle (TripStatus)
-- independent of ContractStatus.
-- One trip can have at most one contract (UNIQUE on TripID
-- inside Contracts enforces the 1:1 side of this relation).
-- CHECK constraint prevents invalid date ranges at DB level.
-- ============================================================
CREATE TABLE Trips (
    TripID          INT             AUTO_INCREMENT PRIMARY KEY,
    Destination     VARCHAR(200)    NOT NULL,
    RegionID        INT             NOT NULL,
    DepartureDate   DATE            NOT NULL,
    ReturnDate      DATE            NOT NULL,
    NumTravelers    INT             NOT NULL
                        CHECK (NumTravelers >= 1),
    TripStatus      ENUM(
                        'upcoming',
                        'ongoing',
                        'completed',
                        'cancelled'
                    )               NOT NULL DEFAULT 'upcoming',
    CONSTRAINT fk_trip_region
        FOREIGN KEY (RegionID) REFERENCES DestinationRegions(RegionID),
    CONSTRAINT chk_trip_dates
        CHECK (ReturnDate > DepartureDate)
);

-- ============================================================
-- 5. CONTRACTS
-- Binding agreement linking Customer × Trip × Plan.
-- TripID UNIQUE enforces one contract per trip (1:1).
-- TotalPremium is intentionally denormalised: premiums are
-- legal commitments that must remain immutable even if the
-- plan's base rate changes after signing. (See report §2.3)
-- DECIMAL(10,2) used throughout for financial amounts —
-- FLOAT introduces binary rounding errors unacceptable in
-- financial records.
-- ============================================================
CREATE TABLE Contracts (
    ContractID      INT             AUTO_INCREMENT PRIMARY KEY,
    CustomerID      INT             NOT NULL,
    TripID          INT             NOT NULL UNIQUE,
    PlanID          INT             NOT NULL,
    SignDate        DATE            NOT NULL,
    TotalPremium    DECIMAL(10, 2)  NOT NULL
                        CHECK (TotalPremium > 0),
    ContractStatus  ENUM(
                        'active',
                        'expired',
                        'cancelled'
                    )               NOT NULL DEFAULT 'active',
    CONSTRAINT fk_contract_customer
        FOREIGN KEY (CustomerID) REFERENCES Customers(CustomerID),
    CONSTRAINT fk_contract_trip
        FOREIGN KEY (TripID) REFERENCES Trips(TripID),
    CONSTRAINT fk_contract_plan
        FOREIGN KEY (PlanID) REFERENCES InsurancePlans(PlanID)
);

-- ============================================================
-- 6. CLAIM TYPES
-- Per-type coverage rules (CoveragePercentage,
-- MaxCoverageAmount). Stored as a table rather than ENUM
-- because these business rules need to be updatable via a
-- standard UPDATE statement without schema migration.
-- ============================================================
CREATE TABLE ClaimTypes (
    ClaimTypeID         INT             AUTO_INCREMENT PRIMARY KEY,
    TypeName            VARCHAR(100)    NOT NULL UNIQUE,
    Description         TEXT,
    CoveragePercentage  DECIMAL(5, 2)   NOT NULL
                            CHECK (CoveragePercentage BETWEEN 0 AND 100),
    MaxCoverageAmount   DECIMAL(10, 2)  NOT NULL
                            CHECK (MaxCoverageAmount > 0)
);

-- ============================================================
-- 7. CLAIMS
-- Compensation request filed against a contract.
-- ClaimTypeID determines which coverage rules apply during
-- assessment. Status is managed by triggers, not by Python.
-- ============================================================
CREATE TABLE Claims (
    ClaimID             INT             AUTO_INCREMENT PRIMARY KEY,
    ContractID          INT             NOT NULL,
    ClaimTypeID         INT             NOT NULL,
    FilingDate          DATE            NOT NULL,
    IncidentDescription TEXT,
    ClaimStatus         ENUM(
                            'pending',
                            'under_review',
                            'approved',
                            'rejected'
                        )               NOT NULL DEFAULT 'pending',
    CONSTRAINT fk_claim_contract
        FOREIGN KEY (ContractID) REFERENCES Contracts(ContractID),
    CONSTRAINT fk_claim_type
        FOREIGN KEY (ClaimTypeID) REFERENCES ClaimTypes(ClaimTypeID)
);

-- ============================================================
-- 8. ASSESSMENTS
-- Assessor's formal decision on a claim. 1:1 with Claims —
-- UNIQUE(ClaimID) prevents double-assessment of the same claim.
-- ApprovedAmount = 0.00 when Result = 'rejected'.
-- ============================================================
CREATE TABLE Assessments (
    AssessmentID    INT             AUTO_INCREMENT PRIMARY KEY,
    ClaimID         INT             NOT NULL UNIQUE,
    AssessmentDate  DATE            NOT NULL,
    AssessorNote    TEXT,
    Result          ENUM(
                        'approved',
                        'rejected'
                    )               NOT NULL,
    ApprovedAmount  DECIMAL(10, 2)  NOT NULL DEFAULT 0.00
                        CHECK (ApprovedAmount >= 0),
    CONSTRAINT fk_assessment_claim
        FOREIGN KEY (ClaimID) REFERENCES Claims(ClaimID)
);

-- ============================================================
-- 9. PAYOUTS
-- Disbursement record. 1:1 with Claims — UNIQUE(ClaimID)
-- prevents double-payment. Created automatically by trigger
-- trg_after_assessment_insert when Result = 'approved'.
-- Direct INSERT by application roles is prohibited by RBAC.
-- ============================================================
CREATE TABLE Payouts (
    PayoutID        INT             AUTO_INCREMENT PRIMARY KEY,
    ClaimID         INT             NOT NULL UNIQUE,
    Amount          DECIMAL(10, 2)  NOT NULL
                        CHECK (Amount > 0),
    PayoutDate      DATE            NOT NULL,
    PaymentMethod   ENUM(
                        'bank_transfer',
                        'cash',
                        'e_wallet'
                    )               NOT NULL DEFAULT 'bank_transfer',
    CONSTRAINT fk_payout_claim
        FOREIGN KEY (ClaimID) REFERENCES Claims(ClaimID)
);