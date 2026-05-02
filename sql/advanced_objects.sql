-- ============================================================
-- TRAVEL INSURANCE MANAGEMENT SYSTEM
-- advanced_objects.sql — Indexes, Views, UDFs, SPs, Triggers, RBAC
-- Project 19 | NEU College of Technology
--
-- PREREQUISITE: schema.sql must be executed first.
-- schema.sql drops the entire database, so all indexes,
-- views, procedures, functions, and triggers are gone before
-- this file runs — no DROP statements needed here.
-- Run order: schema.sql → advanced_objects.sql → sample_data.sql
-- ============================================================

USE TravelInsuranceDB;

-- ============================================================
-- A. INDEXES
-- ============================================================

CREATE INDEX idx_contracts_customer  ON Contracts(CustomerID);
CREATE INDEX idx_contracts_status    ON Contracts(ContractStatus);
CREATE INDEX idx_claims_contract     ON Claims(ContractID);
CREATE INDEX idx_claims_status       ON Claims(ClaimStatus);
CREATE INDEX idx_trips_departure     ON Trips(DepartureDate);

-- ============================================================
-- B. USER-DEFINED FUNCTIONS
-- ============================================================

DELIMITER $$

-- fn_CalculatePremium(PlanID, TripID)
-- Formula: BasePremiumPerPersonPerDay × NumTravelers
--          × TripDurationDays × RegionMultiplier
-- NOT DETERMINISTIC: reads from mutable InsurancePlans / Trips tables.
CREATE FUNCTION fn_CalculatePremium(
    p_PlanID INT,
    p_TripID INT
)
RETURNS DECIMAL(10, 2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_Base      DECIMAL(10, 2) DEFAULT NULL;
    DECLARE v_Multi     DECIMAL(4, 2)  DEFAULT NULL;
    DECLARE v_Days      INT            DEFAULT NULL;
    DECLARE v_Travelers INT            DEFAULT NULL;

    SELECT BasePremiumPerPersonPerDay
    INTO   v_Base
    FROM   InsurancePlans
    WHERE  PlanID = p_PlanID;

    IF v_Base IS NULL THEN
        RETURN NULL;
    END IF;

    SELECT DATEDIFF(t.ReturnDate, t.DepartureDate),
           t.NumTravelers,
           dr.PremiumMultiplier
    INTO   v_Days, v_Travelers, v_Multi
    FROM   Trips t
    JOIN   DestinationRegions dr ON t.RegionID = dr.RegionID
    WHERE  t.TripID = p_TripID;

    IF v_Days IS NULL THEN
        RETURN NULL;
    END IF;

    RETURN v_Base * v_Travelers * v_Days * v_Multi;
END$$

-- fn_GetClaimSuccessRate(ContractID)
-- NOT DETERMINISTIC: reads from mutable Claims / Assessments tables.
CREATE FUNCTION fn_GetClaimSuccessRate(p_ContractID INT)
RETURNS DECIMAL(5, 2)
NOT DETERMINISTIC
READS SQL DATA
BEGIN
    DECLARE v_Total    INT DEFAULT 0;
    DECLARE v_Approved INT DEFAULT 0;

    SELECT COUNT(*)
    INTO   v_Total
    FROM   Claims
    WHERE  ContractID = p_ContractID;

    IF v_Total = 0 THEN
        RETURN 0.00;
    END IF;

    SELECT COUNT(*)
    INTO   v_Approved
    FROM   Claims      c
    JOIN   Assessments a ON c.ClaimID = a.ClaimID
    WHERE  c.ContractID = p_ContractID
      AND  a.Result = 'approved';

    RETURN ROUND((v_Approved / v_Total) * 100, 2);
END$$

DELIMITER ;

-- ============================================================
-- C. VIEWS
-- ============================================================

CREATE VIEW vw_ActiveContracts AS
SELECT
    c.ContractID,
    cu.FullName             AS CustomerName,
    cu.Phone,
    t.Destination,
    dr.RegionName,
    t.DepartureDate,
    t.ReturnDate,
    t.NumTravelers,
    p.PlanName,
    p.MaxClaimsPerYear,
    c.TotalPremium,
    c.ContractStatus
FROM Contracts c
JOIN Customers          cu ON c.CustomerID = cu.CustomerID
JOIN Trips              t  ON c.TripID     = t.TripID
JOIN DestinationRegions dr ON t.RegionID   = dr.RegionID
JOIN InsurancePlans     p  ON c.PlanID     = p.PlanID
WHERE c.ContractStatus = 'active';

CREATE VIEW vw_PendingClaims AS
SELECT
    cl.ClaimID,
    cl.FilingDate,
    cu.FullName             AS CustomerName,
    cu.Phone,
    t.Destination,
    ct.TypeName             AS ClaimType,
    ct.CoveragePercentage,
    ct.MaxCoverageAmount,
    cl.IncidentDescription,
    cl.ClaimStatus
FROM Claims cl
JOIN Contracts      c  ON cl.ContractID  = c.ContractID
JOIN Customers      cu ON c.CustomerID   = cu.CustomerID
JOIN Trips          t  ON c.TripID       = t.TripID
JOIN ClaimTypes     ct ON cl.ClaimTypeID = ct.ClaimTypeID
WHERE cl.ClaimStatus IN ('pending', 'under_review')
ORDER BY cl.FilingDate ASC;

CREATE VIEW vw_MonthlyPayoutSummary AS
SELECT
    YEAR(p.PayoutDate)      AS PayoutYear,
    MONTH(p.PayoutDate)     AS PayoutMonth,
    COUNT(*)                AS NumPayouts,
    SUM(p.Amount)           AS TotalAmountVND,
    ROUND(AVG(p.Amount), 0) AS AvgAmountVND
FROM Payouts p
GROUP BY YEAR(p.PayoutDate), MONTH(p.PayoutDate)
ORDER BY PayoutYear DESC, PayoutMonth DESC;

CREATE VIEW vw_ContractClaimSummary AS
SELECT
    c.ContractID,
    cu.FullName                                                     AS CustomerName,
    t.Destination,
    p.PlanName,
    c.TotalPremium,
    COUNT(cl.ClaimID)                                               AS TotalClaims,
    SUM(CASE WHEN a.Result = 'approved' THEN 1 ELSE 0 END)         AS ApprovedClaims,
    COALESCE(SUM(py.Amount), 0)                                     AS TotalPaidOutVND,
    fn_GetClaimSuccessRate(c.ContractID)                            AS SuccessRatePct
FROM   Contracts        c
JOIN   Customers        cu  ON c.CustomerID  = cu.CustomerID
JOIN   Trips            t   ON c.TripID      = t.TripID
JOIN   InsurancePlans   p   ON c.PlanID      = p.PlanID
LEFT JOIN Claims        cl  ON c.ContractID  = cl.ContractID
LEFT JOIN Assessments   a   ON cl.ClaimID    = a.ClaimID
LEFT JOIN Payouts       py  ON cl.ClaimID    = py.ClaimID
GROUP BY c.ContractID, cu.FullName, t.Destination, p.PlanName, c.TotalPremium;

-- ============================================================
-- D. STORED PROCEDURES
-- ============================================================

DELIMITER $$

-- sp_CreateContract
-- Pre-conditions:
--   (1) InsurancePlan must be active.
--   (2) Trip must be in 'upcoming' status.
--   (3) Departure date must be in the future.
CREATE PROCEDURE sp_CreateContract(
    IN  p_CustomerID   INT,
    IN  p_TripID       INT,
    IN  p_PlanID       INT,
    OUT p_ContractID   INT,
    OUT p_TotalPremium DECIMAL(10, 2)
)
BEGIN
    DECLARE v_PlanActive    BOOLEAN      DEFAULT NULL;
    DECLARE v_TripStatus    VARCHAR(20)  DEFAULT NULL;
    DECLARE v_DepartureDate DATE         DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT IsActive
    INTO   v_PlanActive
    FROM   InsurancePlans
    WHERE  PlanID = p_PlanID;

    IF v_PlanActive IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Insurance plan not found.';
    END IF;

    IF v_PlanActive = FALSE THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Selected insurance plan is inactive.';
    END IF;

    SELECT TripStatus, DepartureDate
    INTO   v_TripStatus, v_DepartureDate
    FROM   Trips
    WHERE  TripID = p_TripID;

    IF v_TripStatus IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Trip not found.';
    END IF;

    IF v_TripStatus != 'upcoming' THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot insure a trip that is not in upcoming status.';
    END IF;

    IF v_DepartureDate <= CURDATE() THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Cannot insure a trip whose departure date is today or in the past.';
    END IF;

    SET p_TotalPremium = fn_CalculatePremium(p_PlanID, p_TripID);

    IF p_TotalPremium IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Premium calculation failed: invalid plan or trip data.';
    END IF;

    INSERT INTO Contracts
        (CustomerID, TripID, PlanID, SignDate, TotalPremium, ContractStatus)
    VALUES
        (p_CustomerID, p_TripID, p_PlanID, CURDATE(), p_TotalPremium, 'active');

    SET p_ContractID = LAST_INSERT_ID();

    COMMIT;
END$$

CREATE PROCEDURE sp_FileClaim(
    IN  p_ContractID  INT,
    IN  p_ClaimTypeID INT,
    IN  p_Description TEXT,
    OUT p_ClaimID     INT
)
BEGIN
    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    INSERT INTO Claims
        (ContractID, ClaimTypeID, FilingDate, IncidentDescription, ClaimStatus)
    VALUES
        (p_ContractID, p_ClaimTypeID, CURDATE(), p_Description, 'under_review');

    SET p_ClaimID = LAST_INSERT_ID();

    COMMIT;
END$$

CREATE PROCEDURE sp_ProcessAssessment(
    IN p_ClaimID        INT,
    IN p_Result         ENUM('approved', 'rejected'),
    IN p_ApprovedAmount DECIMAL(10, 2),
    IN p_Note           TEXT
)
BEGIN
    DECLARE v_ClaimStatus VARCHAR(20) DEFAULT NULL;

    DECLARE EXIT HANDLER FOR SQLEXCEPTION
    BEGIN
        ROLLBACK;
        RESIGNAL;
    END;

    START TRANSACTION;

    SELECT ClaimStatus
    INTO   v_ClaimStatus
    FROM   Claims
    WHERE  ClaimID = p_ClaimID
    FOR UPDATE;

    IF v_ClaimStatus IS NULL THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'Claim not found.';
    END IF;

    IF v_ClaimStatus NOT IN ('pending', 'under_review') THEN
        SIGNAL SQLSTATE '45000'
            SET MESSAGE_TEXT = 'This claim has already been assessed and cannot be re-evaluated.';
    END IF;

    INSERT INTO Assessments
        (ClaimID, AssessmentDate, AssessorNote, Result, ApprovedAmount)
    VALUES
        (p_ClaimID, CURDATE(), p_Note, p_Result, p_ApprovedAmount);

    COMMIT;
END$$

DELIMITER ;

-- ============================================================
-- E. TRIGGERS
--
-- @trigger_disabled guard: sample_data.sql sets this to TRUE
-- before seeding historical records, then resets to NULL.
-- Triggers check: IF @trigger_disabled IS NOT TRUE THEN ...
-- This inverted condition avoids empty THEN branches, which
-- MySQL does not permit.
-- ============================================================

DELIMITER $$

-- trg_before_claim_insert
-- Live mode: enforces contract-active check and annual claim limit.
-- Seed mode (@trigger_disabled = TRUE): skipped entirely.
CREATE TRIGGER trg_before_claim_insert
BEFORE INSERT ON Claims
FOR EACH ROW
BEGIN
    DECLARE v_ContractStatus VARCHAR(20);
    DECLARE v_PlanID         INT;
    DECLARE v_MaxClaims      INT;
    DECLARE v_YearClaimCount INT;

    IF @trigger_disabled IS NOT TRUE THEN

        SELECT ContractStatus, PlanID
        INTO   v_ContractStatus, v_PlanID
        FROM   Contracts
        WHERE  ContractID = NEW.ContractID;

        IF v_ContractStatus IS NULL THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Claim denied: contract not found.';
        END IF;

        IF v_ContractStatus != 'active' THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Claim denied: the linked contract is not active.';
        END IF;

        SELECT MaxClaimsPerYear
        INTO   v_MaxClaims
        FROM   InsurancePlans
        WHERE  PlanID = v_PlanID;

        SELECT COUNT(*)
        INTO   v_YearClaimCount
        FROM   Claims
        WHERE  ContractID = NEW.ContractID
          AND  YEAR(FilingDate) = YEAR(NEW.FilingDate);

        IF v_YearClaimCount >= v_MaxClaims THEN
            SIGNAL SQLSTATE '45000'
                SET MESSAGE_TEXT = 'Claim denied: annual claim limit for this plan has been reached.';
        END IF;

    END IF;
END$$

-- trg_after_assessment_insert
-- Live mode: updates ClaimStatus and auto-creates Payout if approved.
-- Seed mode (@trigger_disabled = TRUE): skipped; Payouts inserted
-- manually in sample_data.sql for historical records.
CREATE TRIGGER trg_after_assessment_insert
AFTER INSERT ON Assessments
FOR EACH ROW
BEGIN
    IF @trigger_disabled IS NOT TRUE THEN

        IF NEW.Result = 'approved' THEN

            UPDATE Claims
            SET    ClaimStatus = 'approved'
            WHERE  ClaimID = NEW.ClaimID;

            INSERT INTO Payouts (ClaimID, Amount, PayoutDate, PaymentMethod)
            VALUES (NEW.ClaimID, NEW.ApprovedAmount, CURDATE(), 'bank_transfer');

        ELSE

            UPDATE Claims
            SET    ClaimStatus = 'rejected'
            WHERE  ClaimID = NEW.ClaimID;

        END IF;

    END IF;
END$$

-- trg_after_trip_status_update
-- No seed-mode guard needed: sample_data.sql sets ContractStatus
-- directly via INSERT, never via UPDATE on Trips.
CREATE TRIGGER trg_after_trip_status_update
AFTER UPDATE ON Trips
FOR EACH ROW
BEGIN
    IF NEW.TripStatus IN ('completed', 'cancelled')
       AND OLD.TripStatus NOT IN ('completed', 'cancelled') THEN

        UPDATE Contracts
        SET    ContractStatus = CASE
                   WHEN NEW.TripStatus = 'completed' THEN 'expired'
                   ELSE 'cancelled'
               END
        WHERE  TripID         = NEW.TripID
          AND  ContractStatus = 'active';

    END IF;
END$$

DELIMITER ;

-- ============================================================
-- F. USER ROLES & ACCESS CONTROL (RBAC)
-- ============================================================

DROP USER IF EXISTS 'tripAssure_agent'@'localhost';
DROP USER IF EXISTS 'tripAssure_assessor'@'localhost';
DROP USER IF EXISTS 'tripAssure_admin'@'localhost';

CREATE USER 'tripAssure_agent'@'localhost'     IDENTIFIED BY 'AgentPass@2025';
CREATE USER 'tripAssure_assessor'@'localhost'  IDENTIFIED BY 'AssessorPass@2025';
CREATE USER 'tripAssure_admin'@'localhost'     IDENTIFIED BY 'AdminPass@2025';

GRANT SELECT         ON TravelInsuranceDB.Customers               TO 'tripAssure_agent'@'localhost';
GRANT INSERT         ON TravelInsuranceDB.Customers               TO 'tripAssure_agent'@'localhost';
GRANT SELECT, INSERT ON TravelInsuranceDB.Trips                   TO 'tripAssure_agent'@'localhost';
GRANT SELECT, INSERT ON TravelInsuranceDB.Contracts               TO 'tripAssure_agent'@'localhost';
GRANT SELECT, INSERT ON TravelInsuranceDB.Claims                  TO 'tripAssure_agent'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.InsurancePlans          TO 'tripAssure_agent'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.ClaimTypes              TO 'tripAssure_agent'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.DestinationRegions      TO 'tripAssure_agent'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.vw_ActiveContracts      TO 'tripAssure_agent'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.vw_ContractClaimSummary TO 'tripAssure_agent'@'localhost';
GRANT EXECUTE        ON PROCEDURE TravelInsuranceDB.sp_CreateContract
                     TO 'tripAssure_agent'@'localhost';
GRANT EXECUTE        ON PROCEDURE TravelInsuranceDB.sp_FileClaim
                     TO 'tripAssure_agent'@'localhost';
GRANT EXECUTE        ON FUNCTION  TravelInsuranceDB.fn_CalculatePremium
                     TO 'tripAssure_agent'@'localhost';

GRANT SELECT         ON TravelInsuranceDB.Claims                  TO 'tripAssure_assessor'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.Contracts               TO 'tripAssure_assessor'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.Customers               TO 'tripAssure_assessor'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.ClaimTypes              TO 'tripAssure_assessor'@'localhost';
GRANT SELECT, INSERT ON TravelInsuranceDB.Assessments             TO 'tripAssure_assessor'@'localhost';
GRANT SELECT         ON TravelInsuranceDB.vw_PendingClaims        TO 'tripAssure_assessor'@'localhost';
GRANT EXECUTE        ON PROCEDURE TravelInsuranceDB.sp_ProcessAssessment
                     TO 'tripAssure_assessor'@'localhost';
GRANT EXECUTE        ON FUNCTION  TravelInsuranceDB.fn_GetClaimSuccessRate
                     TO 'tripAssure_assessor'@'localhost';

GRANT ALL PRIVILEGES ON TravelInsuranceDB.* TO 'tripAssure_admin'@'localhost';

FLUSH PRIVILEGES;