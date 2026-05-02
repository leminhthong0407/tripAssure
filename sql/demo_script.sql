-- ============================================================
-- DEMO SCRIPT — Step 8
-- TripAssure Travel Insurance Management System
-- Presentation scenario: follow one traveller end-to-end.
--
-- IDEMPOTENT: Safe to run multiple times.
-- Scene 2 cleans up Nguyen Van An before re-inserting.
-- Scene 4 creates self-contained test data independent of
-- sample_data years.
--
-- NOTE: @trigger_disabled is NOT set here — all triggers run
-- in live mode throughout the demo. sample_data.sql resets
-- @trigger_disabled = NULL at the end of seeding, so this
-- session inherits live behaviour by default.
-- ============================================================

USE TravelInsuranceDB;

-- Disable safe update mode for this session.
-- Required because several UPDATE/DELETE statements use
-- session variables or non-PK WHERE conditions.
SET SQL_SAFE_UPDATES = 0;

-- Reset all session variables so stale values from a prior
-- run never bleed into this session.
SET @new_customer_id  = NULL;
SET @new_trip_id      = NULL;
SET @new_contract_id  = NULL;
SET @premium          = NULL;
SET @new_claim_id     = NULL;
SET @test_customer_id = NULL;
SET @test_trip_id     = NULL;
SET @test_contract_id = NULL;
SET @test_claim_id    = NULL;
SET @blocked_claim_id = NULL;

-- ============================================================
-- SCENE 1 — "Let me show you the system from a fresh state"
-- ============================================================

-- What insurance plans do we offer?
SELECT PlanID, PlanName,
       FORMAT(BasePremiumPerPersonPerDay, 0) AS PricePerPersonPerDay_VND,
       MaxClaimsPerYear,
       IsActive
FROM InsurancePlans;

-- Where can customers travel?
SELECT RegionName, PremiumMultiplier
FROM DestinationRegions
ORDER BY PremiumMultiplier;

-- How many contracts by status right now?
SELECT ContractStatus, COUNT(*) AS Total
FROM Contracts
GROUP BY ContractStatus;

-- ============================================================
-- SCENE 2 — "A new customer walks in — Nguyen Van An"
-- Enroll customer, plan a trip, create contract.
-- ============================================================

-- Idempotent cleanup: delete Van An's data from any prior run.
-- FK children first: Payouts → Assessments → Claims → Contracts → Trips → Customer.
SET FOREIGN_KEY_CHECKS = 0;

DELETE py FROM Payouts py
  JOIN Claims    cl ON py.ClaimID    = cl.ClaimID
  JOIN Contracts co ON cl.ContractID = co.ContractID
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001098099001';

DELETE a FROM Assessments a
  JOIN Claims    cl ON a.ClaimID     = cl.ClaimID
  JOIN Contracts co ON cl.ContractID = co.ContractID
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001098099001';

DELETE cl FROM Claims cl
  JOIN Contracts co ON cl.ContractID = co.ContractID
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001098099001';

DELETE co FROM Contracts co
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001098099001';

-- Delete the orphan Trip by PK lookup via subquery to avoid
-- safe-update and non-key WHERE issues.
DELETE FROM Trips
WHERE TripID IN (
    SELECT TripID FROM (
        SELECT TripID FROM Trips
        WHERE Destination   = 'Tokyo, Japan'
          AND DepartureDate = '2026-09-01'
          AND NumTravelers  = 2
    ) AS t
);

DELETE FROM Customers WHERE NationalID = '001098099001';

SET FOREIGN_KEY_CHECKS = 1;

-- Step 2a: Register the customer.
INSERT INTO Customers (FullName, DateOfBirth, NationalID, Phone, Email, Address)
VALUES ('Nguyen Van An', '1998-06-15', '001098099001', '0987654321',
        'an.nguyen@gmail.com', '99 Dinh Tien Hoang, Hoan Kiem, Ha Noi');

SET @new_customer_id = LAST_INSERT_ID();
SELECT @new_customer_id AS NewCustomerID;

-- Step 2b: Tokyo trip — 2026-09-01 to 2026-09-08, 2 people.
INSERT INTO Trips (Destination, RegionID, DepartureDate, ReturnDate, NumTravelers, TripStatus)
VALUES ('Tokyo, Japan', 3, '2026-09-01', '2026-09-08', 2, 'upcoming');

SET @new_trip_id = LAST_INSERT_ID();
SELECT @new_trip_id AS NewTripID;

-- Step 2c: Preview premium before committing.
-- Asia Premium (PlanID=3): 45,000 × 2 persons × 7 days × 1.50 = 945,000 VND
SELECT fn_CalculatePremium(3, @new_trip_id) AS EstimatedPremium_VND;

-- Step 2d: Customer agrees — create the contract.
CALL sp_CreateContract(@new_customer_id, @new_trip_id, 3, @new_contract_id, @premium);
SELECT @new_contract_id AS ContractID, FORMAT(@premium, 0) AS Premium_VND;

-- Verify it appears in the active contracts view.
SELECT * FROM vw_ActiveContracts WHERE ContractID = @new_contract_id;

-- ============================================================
-- SCENE 3 — "He lands in Tokyo and loses his bag"
-- File a baggage loss claim — trigger validation passes.
-- ============================================================

CALL sp_FileClaim(
    @new_contract_id,
    3,  -- ClaimTypeID 3 = Baggage Loss
    'Checked bag not delivered at Narita Airport. Japan Airlines ref JAL-20260902-7734.',
    @new_claim_id
);
SELECT @new_claim_id AS NewClaimID;

-- Claim now appears in the assessor queue.
SELECT * FROM vw_PendingClaims;

-- ============================================================
-- SCENE 4 — "Now let's try to break the rules"
-- Self-contained test: Basic Domestic (MaxClaimsPerYear=2).
-- Uses DATE_ADD(CURDATE()) so the trigger's YEAR() check
-- always fires in the current calendar year.
-- ============================================================

-- Idempotent cleanup for Scene 4 test data.
SET FOREIGN_KEY_CHECKS = 0;

DELETE py FROM Payouts py
  JOIN Claims    cl ON py.ClaimID    = cl.ClaimID
  JOIN Contracts co ON cl.ContractID = co.ContractID
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001111999001';

DELETE a FROM Assessments a
  JOIN Claims    cl ON a.ClaimID     = cl.ClaimID
  JOIN Contracts co ON cl.ContractID = co.ContractID
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001111999001';

DELETE cl FROM Claims cl
  JOIN Contracts co ON cl.ContractID = co.ContractID
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001111999001';

DELETE co FROM Contracts co
  JOIN Customers cu ON co.CustomerID = cu.CustomerID
  WHERE cu.NationalID = '001111999001';

DELETE FROM Trips
WHERE TripID IN (
    SELECT TripID FROM (
        SELECT TripID FROM Trips
        WHERE Destination = 'Da Lat, Lam Dong (Demo Test)'
          AND NumTravelers = 1
    ) AS t
);

DELETE FROM Customers WHERE NationalID = '001111999001';

SET FOREIGN_KEY_CHECKS = 1;

-- Create self-contained test customer + trip + contract.
INSERT INTO Customers (FullName, DateOfBirth, NationalID, Phone)
VALUES ('Demo Test User', '1990-01-01', '001111999001', '0900000000');
SET @test_customer_id = LAST_INSERT_ID();

INSERT INTO Trips (Destination, RegionID, DepartureDate, ReturnDate, NumTravelers, TripStatus)
VALUES ('Da Lat, Lam Dong (Demo Test)', 1,
        DATE_ADD(CURDATE(), INTERVAL 30 DAY),
        DATE_ADD(CURDATE(), INTERVAL 34 DAY),
        1, 'upcoming');
SET @test_trip_id = LAST_INSERT_ID();

CALL sp_CreateContract(@test_customer_id, @test_trip_id, 1, @test_contract_id, @premium);
SELECT @test_contract_id AS TestContractID,
       FORMAT(@premium, 0) AS Premium_VND,
       'MaxClaimsPerYear = 2' AS PlanLimit;

-- Claim #1 — succeeds (1 of 2).
CALL sp_FileClaim(@test_contract_id, 2, 'Claim #1: flight delayed 7 hours.', @test_claim_id);
SELECT @test_claim_id AS Claim1_ID, '1 of 2 — should succeed' AS Expected;

-- Claim #2 — succeeds (2 of 2).
CALL sp_FileClaim(@test_contract_id, 3, 'Claim #2: baggage delayed on arrival.', @test_claim_id);
SELECT @test_claim_id AS Claim2_ID, '2 of 2 — should succeed' AS Expected;

-- Claim #3 — TRIGGER BLOCKS THIS (uncomment for live demo moment).
-- CALL sp_FileClaim(@test_contract_id, 1, 'Claim #3: trying to exceed limit...', @blocked_claim_id);
-- Expected: "Claim denied: annual claim limit for this plan has been reached."

-- Also: filing against a non-active contract.
-- CALL sp_FileClaim(8, 1, 'Filing against cancelled contract...', @blocked_claim_id);
-- Expected: "Claim denied: the linked contract is not active."

-- ============================================================
-- SCENE 5 — "Assessor reviews An's baggage claim and approves it"
-- trg_after_assessment_insert auto-creates the Payout row.
-- ============================================================

-- Before assessment: confirm no payout exists yet.
SELECT * FROM Payouts WHERE ClaimID = @new_claim_id;

CALL sp_ProcessAssessment(
    @new_claim_id,
    'approved',
    4500000.00,
    'JAL loss report verified. Luggage declared value 5,000,000 VND. Approved at 90% per Baggage Loss policy.'
);

-- Payout row automatically created by trg_after_assessment_insert.
SELECT * FROM Payouts WHERE ClaimID = @new_claim_id;

-- ClaimStatus automatically updated to approved.
SELECT ClaimID, ClaimStatus FROM Claims WHERE ClaimID = @new_claim_id;

-- ============================================================
-- SCENE 6 — "Admin opens the reports dashboard"
-- ============================================================

-- Monthly payout summary.
SELECT * FROM vw_MonthlyPayoutSummary;

-- Which claim types cost the company the most?
SELECT
    ct.TypeName,
    COUNT(cl.ClaimID)                                               AS TotalClaims,
    SUM(CASE WHEN a.Result = 'approved' THEN 1 ELSE 0 END)         AS Approved,
    COALESCE(SUM(p.Amount), 0)                                      AS TotalPaidOut_VND
FROM ClaimTypes ct
LEFT JOIN Claims      cl ON ct.ClaimTypeID = cl.ClaimTypeID
LEFT JOIN Assessments a  ON cl.ClaimID     = a.ClaimID
LEFT JOIN Payouts     p  ON cl.ClaimID     = p.ClaimID
GROUP BY ct.ClaimTypeID, ct.TypeName
ORDER BY TotalPaidOut_VND DESC;

-- Contract-level summary with UDF success rate.
SELECT ContractID, CustomerName, Destination, TotalPremium,
       TotalClaims, ApprovedClaims, TotalPaidOutVND, SuccessRatePct
FROM vw_ContractClaimSummary;

-- Profitability check.
SELECT
    SUM(c.TotalPremium)                                AS TotalPremiumCollected_VND,
    COALESCE(SUM(p.Amount), 0)                         AS TotalPayoutsIssued_VND,
    SUM(c.TotalPremium) - COALESCE(SUM(p.Amount), 0)  AS NetRevenue_VND
FROM Contracts c
LEFT JOIN Claims      cl ON c.ContractID = cl.ContractID
LEFT JOIN Payouts     p  ON cl.ClaimID   = p.ClaimID;

-- ============================================================
-- SCENE 7 — "An's trip ends — trigger keeps the DB clean"
-- ============================================================

-- Before update.
SELECT TripStatus     FROM Trips     WHERE TripID     = @new_trip_id;
SELECT ContractStatus FROM Contracts WHERE ContractID = @new_contract_id;

-- Mark trip completed — trg_after_trip_status_update fires.
-- Uses PK directly; SQL_SAFE_UPDATES = 0 ensures session
-- variables in WHERE are also accepted.
UPDATE Trips
SET    TripStatus = 'completed'
WHERE  TripID = @new_trip_id;

-- After: ContractStatus automatically changed to 'expired'.
SELECT TripStatus     FROM Trips     WHERE TripID     = @new_trip_id;
SELECT ContractStatus FROM Contracts WHERE ContractID = @new_contract_id;

-- Restore safe update mode.
SET SQL_SAFE_UPDATES = 1;

-- ============================================================
-- END OF DEMO
-- Full story: Customer enrolled → Trip created → Contract signed
--             → Premium calculated (UDF) → Claim filed
--             → Trigger validated annual limits
--             → Assessment recorded → Payout auto-created (trigger)
--             → Trip completed → Contract auto-expired (trigger)
--             → Admin reports show full financial picture
-- ============================================================