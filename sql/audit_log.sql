-- ============================================================
-- AUDIT LOG — TripAssure Security Layer
-- Append to advanced_objects.sql hoặc chạy riêng sau advanced_objects.sql
--
-- Ghi lại mọi thay đổi trạng thái quan trọng:
--   Contracts: ContractStatus thay đổi
--   Claims:    ClaimStatus thay đổi
--   Payouts:   mọi INSERT (tạo mới payout)
--
-- DB_USER() trả về user đang kết nối tại thời điểm thay đổi
-- → Kể cả thay đổi do trigger gây ra cũng được ghi
-- ============================================================

USE TravelInsuranceDB;

-- ============================================================
-- BẢNG AUDIT LOG
-- ============================================================
CREATE TABLE IF NOT EXISTS AuditLog (
    LogID       INT             AUTO_INCREMENT PRIMARY KEY,
    TableName   VARCHAR(50)     NOT NULL,
    Action      ENUM('INSERT','UPDATE','DELETE') NOT NULL,
    RecordID    INT             NOT NULL,
    DBUser      VARCHAR(100)    NOT NULL DEFAULT (CURRENT_USER()),
    ChangedAt   DATETIME        NOT NULL DEFAULT NOW(),
    OldStatus   VARCHAR(50),                    -- Trạng thái trước khi thay đổi
    NewStatus   VARCHAR(50),                    -- Trạng thái sau khi thay đổi
    Note        VARCHAR(255)                    -- Context thêm nếu có
);

-- ============================================================
-- TRIGGER 1: Audit ContractStatus changes
-- Khi nào: mỗi lần ContractStatus thay đổi (do agent, trigger trip, SP)
-- Ghi lại: ai thay đổi, từ status nào sang status nào, lúc mấy giờ
-- ============================================================
DELIMITER $$

CREATE TRIGGER trg_audit_contract_status
AFTER UPDATE ON Contracts
FOR EACH ROW
BEGIN
    IF OLD.ContractStatus != NEW.ContractStatus THEN
        INSERT INTO AuditLog (TableName, Action, RecordID, OldStatus, NewStatus)
        VALUES ('Contracts', 'UPDATE', NEW.ContractID,
                OLD.ContractStatus, NEW.ContractStatus);
    END IF;
END$$

-- ============================================================
-- TRIGGER 2: Audit ClaimStatus changes
-- Khi nào: mỗi lần ClaimStatus thay đổi (thường do trg_after_assessment_insert)
-- ============================================================
CREATE TRIGGER trg_audit_claim_status
AFTER UPDATE ON Claims
FOR EACH ROW
BEGIN
    IF OLD.ClaimStatus != NEW.ClaimStatus THEN
        INSERT INTO AuditLog (TableName, Action, RecordID, OldStatus, NewStatus)
        VALUES ('Claims', 'UPDATE', NEW.ClaimID,
                OLD.ClaimStatus, NEW.ClaimStatus);
    END IF;
END$$

-- ============================================================
-- TRIGGER 3: Audit Payout creation
-- Khi nào: mỗi lần Payout được tạo (chỉ qua trigger, không ai INSERT trực tiếp)
-- Ghi lại: ClaimID nào, ai trigger, lúc nào
-- ============================================================
CREATE TRIGGER trg_audit_payout_insert
AFTER INSERT ON Payouts
FOR EACH ROW
BEGIN
    INSERT INTO AuditLog (TableName, Action, RecordID, NewStatus,
                          Note)
    VALUES ('Payouts', 'INSERT', NEW.PayoutID, 'created',
            CONCAT('ClaimID=', NEW.ClaimID, ' Amount=', NEW.Amount));
END$$

DELIMITER ;

-- ============================================================
-- GRANT: Admin có thể đọc AuditLog, không ai khác
-- ============================================================
GRANT SELECT ON TravelInsuranceDB.AuditLog TO 'tripAssure_admin'@'localhost';

FLUSH PRIVILEGES;

-- ============================================================
-- VERIFY
-- ============================================================
-- Chạy thử: UPDATE một contract và xem AuditLog
-- UPDATE Contracts SET ContractStatus = 'expired' WHERE ContractID = 1;
-- SELECT * FROM AuditLog;
-- ============================================================
