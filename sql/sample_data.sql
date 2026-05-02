-- ============================================================
-- TRAVEL INSURANCE MANAGEMENT SYSTEM
-- sample_data.sql — Seed Data
-- Project 19 | NEU College of Technology
--
-- IDEMPOTENT: Safe to run multiple times.
-- PREREQUISITE: schema.sql AND advanced_objects.sql first.
-- Run order: schema.sql → advanced_objects.sql → sample_data.sql
--
-- Trigger bypass: @trigger_disabled = TRUE tells
-- trg_before_claim_insert and trg_after_assessment_insert
-- to skip live-operation guards so historical records
-- (claims against expired contracts, pre-decided assessments)
-- can be inserted cleanly. Reset to NULL at end of file.
--
-- Dates: active/ongoing data uses 2026 dates so the demo
-- remains valid through at least 2026-06-01.
-- ============================================================

USE TravelInsuranceDB;

-- ============================================================
-- CLEAN SLATE
-- ============================================================
SET FOREIGN_KEY_CHECKS = 0;

TRUNCATE TABLE Payouts;
TRUNCATE TABLE Assessments;
TRUNCATE TABLE Claims;
TRUNCATE TABLE Contracts;
TRUNCATE TABLE Trips;
TRUNCATE TABLE Customers;
TRUNCATE TABLE ClaimTypes;
TRUNCATE TABLE InsurancePlans;
TRUNCATE TABLE DestinationRegions;

SET FOREIGN_KEY_CHECKS = 1;

-- Bypass trigger validations for historical seed data.
SET @trigger_disabled = TRUE;

-- ============================================================
-- 1. DESTINATION REGIONS
-- ============================================================
INSERT INTO DestinationRegions (RegionName, PremiumMultiplier, Description) VALUES
('Domestic Vietnam',        1.00, 'All domestic destinations within Vietnam'),
('Southeast Asia',          1.30, 'Thailand, Singapore, Malaysia, Indonesia, Cambodia'),
('East Asia',               1.50, 'Japan, South Korea, China, Taiwan'),
('Europe & North America',  2.20, 'EU countries, UK, USA, Canada — high medical cost zones'),
('Australia & New Zealand', 1.80, 'Oceania region');

-- ============================================================
-- 2. INSURANCE PLANS
-- ============================================================
INSERT INTO InsurancePlans
    (PlanName, Description, BasePremiumPerPersonPerDay, MaxClaimsPerYear, IsActive)
VALUES
('Basic Domestic',
 'Covers trip cancellation and minor medical emergencies for domestic travel.',
 15000.00, 2, TRUE),

('SEA Explorer',
 'Designed for Southeast Asia travel. Covers cancellation, delay, baggage loss and medical.',
 28000.00, 3, TRUE),

('Asia Premium',
 'Comprehensive coverage for East Asia. Includes medical evacuation.',
 45000.00, 3, TRUE),

('Global Elite',
 'Full coverage for Europe and Americas. Unlimited medical coverage up to 200M VND.',
 90000.00, 4, TRUE),

('Backpacker Budget',
 'Low-cost option for young travellers. Covers baggage and emergency only.',
 12000.00, 1, FALSE);   -- Discontinued — validates IsActive check in sp_CreateContract

-- ============================================================
-- 3. CLAIM TYPES
-- ============================================================
INSERT INTO ClaimTypes (TypeName, Description, CoveragePercentage, MaxCoverageAmount) VALUES
('Trip Cancellation',
 'Customer cancels before departure due to medical, family emergency, or natural disaster.',
 80.00, 20000000.00),

('Trip Delay',
 'Flight or transport delayed over 6 hours. Covers accommodation and meals.',
 100.00, 3000000.00),

('Baggage Loss',
 'Checked baggage permanently lost or damaged by carrier.',
 90.00, 8000000.00),

('Medical Emergency',
 'Hospitalization or emergency treatment during trip.',
 100.00, 50000000.00),

('Emergency Evacuation',
 'Medical evacuation to nearest appropriate medical facility.',
 100.00, 90000000.00);

-- ============================================================
-- 4. CUSTOMERS
-- ============================================================
INSERT INTO Customers (FullName, DateOfBirth, NationalID, Phone, Email, Address) VALUES
('Nguyen Thi Lan',    '1995-03-12', '001095012345', '0901234567', 'lan.nguyen@gmail.com',    '12 Tran Phu, Hoan Kiem, Ha Noi'),
('Tran Minh Duc',     '1990-07-25', '001090078912', '0912345678', 'duc.tran@yahoo.com',      '45 Le Loi, Hai Chau, Da Nang'),
('Pham Thi Thu Hang', '1988-11-03', '001088045678', '0923456789', 'hang.pham@outlook.com',   '78 Nguyen Hue, Quan 1, Ho Chi Minh'),
('Le Van Cuong',      '2000-05-18', '001200123456', '0934567890', 'cuong.le@student.neu.vn', '23 Chua Boc, Dong Da, Ha Noi'),
('Vo Thi Bich Ngoc',  '1983-09-30', '001083067890', '0945678901', 'ngoc.vo@gmail.com',       '156 Hoang Dieu, Ngu Hanh Son, Da Nang');

-- ============================================================
-- 5. TRIPS
-- Completed/cancelled trips: historical 2025 dates (fine).
-- Ongoing trip: 2026-04-28 → 2026-05-05 (currently ongoing).
-- Upcoming trips: 2026 departures (valid through 2026-06-01).
-- Cancelled trip: historical 2025 date (fine).
--
-- Premium cross-check (formula: Base × Travelers × Days × Multiplier):
--   Trip 1 (Da Lat):    15000 × 2 × 4 × 1.00 =   120,000 VND
--   Trip 2 (Bangkok):   28000 × 1 × 7 × 1.30 =   254,800 VND
--   Trip 3 (Tokyo):     45000 × 2 × 7 × 1.50 =   945,000 VND
--   Trip 4 (Singapore): 28000 × 3 × 7 × 1.30 =   764,400 VND
--   Trip 5 (Paris):     90000 × 2 × 10 × 2.20 = 3,960,000 VND
--   Trip 6 (Seoul):     45000 × 1 × 7 × 1.50 =   472,500 VND
--   Trip 7 (Sydney):    45000 × 2 × 10 × 1.80 = 1,620,000 VND
--   Trip 8 (Hoi An):    15000 × 4 × 3 × 1.00 =   180,000 VND
-- ============================================================
INSERT INTO Trips (Destination, RegionID, DepartureDate, ReturnDate, NumTravelers, TripStatus) VALUES
-- Completed trips (historical 2025)
('Da Lat, Lam Dong',           1, '2025-01-10', '2025-01-14', 2, 'completed'),  -- TripID 1
('Bangkok, Thailand',          2, '2025-02-20', '2025-02-27', 1, 'completed'),  -- TripID 2
('Tokyo, Japan',               3, '2025-03-15', '2025-03-22', 2, 'completed'),  -- TripID 3

-- Ongoing trip (currently in progress as of 2026-05-01)
('Singapore',                  2, '2026-04-28', '2026-05-05', 3, 'ongoing'),    -- TripID 4

-- Upcoming trips (2026 — valid through at least 2026-06-01)
('Paris, France',              4, '2026-06-10', '2026-06-20', 2, 'upcoming'),   -- TripID 5
('Seoul, South Korea',         3, '2026-07-01', '2026-07-08', 1, 'upcoming'),   -- TripID 6
('Sydney, Australia',          5, '2026-08-15', '2026-08-25', 2, 'upcoming'),   -- TripID 7

-- Cancelled trip (historical 2025)
('Hoi An, Quang Nam',          1, '2025-04-05', '2025-04-08', 4, 'cancelled');  -- TripID 8

-- ============================================================
-- 6. CONTRACTS
-- ContractStatus set directly — bypasses trg_after_trip_status_update
-- which is a live-operation trigger, not a historical constraint.
-- ============================================================
INSERT INTO Contracts
    (CustomerID, TripID, PlanID, SignDate, TotalPremium, ContractStatus)
VALUES
(1, 1, 1, '2025-01-05',   120000.00,  'expired'),   -- Lan  / Da Lat    / Basic Domestic
(2, 2, 2, '2025-02-15',   254800.00,  'expired'),   -- Duc  / Bangkok   / SEA Explorer
(3, 3, 3, '2025-03-10',   945000.00,  'expired'),   -- Hang / Tokyo     / Asia Premium
(4, 4, 2, '2026-04-20',   764400.00,  'active'),    -- Cuong/ Singapore / SEA Explorer
(1, 5, 4, '2026-04-25',  3960000.00,  'active'),    -- Lan  / Paris     / Global Elite
(2, 6, 3, '2026-04-25',   472500.00,  'active'),    -- Duc  / Seoul     / Asia Premium
(5, 7, 3, '2026-04-28',  1620000.00,  'active'),    -- Ngoc / Sydney    / Asia Premium
(3, 8, 1, '2025-04-01',   180000.00,  'cancelled'); -- Hang / Hoi An    / Basic Domestic

-- ============================================================
-- 7. CLAIMS
-- Inserted with @trigger_disabled = TRUE so that
-- trg_before_claim_insert does not block historical claims
-- filed against expired/cancelled contracts.
-- ============================================================
INSERT INTO Claims
    (ContractID, ClaimTypeID, FilingDate, IncidentDescription, ClaimStatus)
VALUES
-- ContractID 1 (expired): Lan's Da Lat — baggage lost by carrier
(1, 3, '2025-01-13',
 'Checked luggage lost by VietJet Air on return flight. Reported immediately at airport. File number VJ-2025-0113.',
 'approved'),

-- ContractID 2 (expired): Duc's Bangkok — flight delayed 9 hours
(2, 2, '2025-02-21',
 'Outbound Bangkok Air flight delayed 9 hours due to engine check. Stranded at Suvarnabhumi Airport overnight.',
 'approved'),

-- ContractID 3 (expired): Hang's Tokyo — medical emergency
(3, 4, '2025-03-18',
 'Acute appendicitis. Emergency surgery at Shinjuku Medical Center, Tokyo. Hospitalized 3 nights. Total bill 85,000 JPY.',
 'approved'),

-- ContractID 3 (expired): trip cancellation — rejected (trip actually proceeded)
(3, 1, '2025-03-14',
 'Filed trip cancellation in advance of illness but trip proceeded — claim later rejected by assessor.',
 'rejected'),

-- ContractID 4 (active, ongoing): Cuong's Singapore — LIVE PENDING ITEM for assessor demo
(4, 3, '2026-04-29',
 'Baggage not delivered for 18 hours after landing at Changi Airport. Filed with Singapore Airlines.',
 'under_review'),

-- ContractID 8 (cancelled): Hang's Hoi An — trip cancellation due to flooding
(8, 1, '2025-04-03',
 'Entire group trip to Hoi An cancelled due to flooding in Quang Nam province reported on April 3.',
 'approved');

-- ============================================================
-- 8. ASSESSMENTS & PAYOUTS
-- Inserted directly because @trigger_disabled = TRUE suppresses
-- trg_after_assessment_insert. Payouts for approved claims
-- must therefore be inserted manually here.
-- In live operation the trigger handles this automatically.
--
--   Claim 1 (Baggage Loss)      → approved → Payout 2,880,000
--   Claim 2 (Trip Delay)        → approved → Payout 3,000,000
--   Claim 3 (Medical Emergency) → approved → Payout 14,200,000
--   Claim 4 (Trip Cancellation) → rejected → no Payout
--   Claim 5 (Baggage Loss)      → under_review → no Assessment (live demo item)
--   Claim 6 (Trip Cancellation) → approved → Payout 144,000
-- ============================================================

INSERT INTO Assessments (ClaimID, AssessmentDate, AssessorNote, Result, ApprovedAmount)
VALUES (1, '2025-01-15',
 'Customer submitted carrier loss report and boarding pass. Approved at 90% of declared baggage value of 3,200,000 VND.',
 'approved', 2880000.00);
INSERT INTO Payouts (ClaimID, Amount, PayoutDate, PaymentMethod)
VALUES (1, 2880000.00, '2025-01-15', 'bank_transfer');

INSERT INTO Assessments (ClaimID, AssessmentDate, AssessorNote, Result, ApprovedAmount)
VALUES (2, '2025-02-25',
 'Delay confirmed via airline official notice. Receipts for airport hotel and meals submitted. Approved at plan ceiling.',
 'approved', 3000000.00);
INSERT INTO Payouts (ClaimID, Amount, PayoutDate, PaymentMethod)
VALUES (2, 3000000.00, '2025-02-25', 'bank_transfer');

INSERT INTO Assessments (ClaimID, AssessmentDate, AssessorNote, Result, ApprovedAmount)
VALUES (3, '2025-03-25',
 'Hospital invoice and surgical records verified. Total cost 14,200,000 VND equivalent. Approved in full.',
 'approved', 14200000.00);
INSERT INTO Payouts (ClaimID, Amount, PayoutDate, PaymentMethod)
VALUES (3, 14200000.00, '2025-03-25', 'bank_transfer');

INSERT INTO Assessments (ClaimID, AssessmentDate, AssessorNote, Result, ApprovedAmount)
VALUES (4, '2025-03-26',
 'Customer filed cancellation claim but departure records confirm trip proceeded. Claim rejected.',
 'rejected', 0.00);
-- No Payout for rejected claim.

-- Claim 5: no Assessment yet — intentional live demo item.

INSERT INTO Assessments (ClaimID, AssessmentDate, AssessorNote, Result, ApprovedAmount)
VALUES (6, '2025-04-04',
 'Provincial flooding notice confirmed. Group tour cancellation fee invoices submitted. Approved at 80% coverage.',
 'approved', 144000.00);
INSERT INTO Payouts (ClaimID, Amount, PayoutDate, PaymentMethod)
VALUES (6, 144000.00, '2025-04-04', 'bank_transfer');

-- ============================================================
-- Restore live-operation trigger behaviour.
-- ============================================================
SET @trigger_disabled = NULL;

-- ============================================================
-- SEED COMPLETE
--   DestinationRegions : 5 rows
--   InsurancePlans     : 5 rows (1 inactive)
--   ClaimTypes         : 5 rows
--   Customers          : 5 rows
--   Trips              : 8 rows (3 completed, 1 ongoing, 3 upcoming, 1 cancelled)
--   Contracts          : 8 rows (3 expired, 4 active, 1 cancelled)
--   Claims             : 6 rows (3 approved, 1 rejected, 1 under_review, 1 approved)
--   Assessments        : 5 rows (Claim 5 intentionally not yet assessed)
--   Payouts            : 4 rows
-- ============================================================