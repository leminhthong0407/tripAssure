-- ============================================================
-- DEMO AUDIT LOG — TripAssure Security Layer
-- Chạy SAU khi đã chạy audit_log.sql
--
-- Kịch bản: minh họa AuditLog ghi nhận tự động
-- 3 tình huống:
--   1. Contract bị expire khi trip hoàn thành  → trg_audit_contract_status
--   2. Claim được duyệt                         → trg_audit_claim_status
--   3. Payout được tạo tự động                  → trg_audit_payout_insert
-- ============================================================

USE TravelInsuranceDB;
SET SQL_SAFE_UPDATES = 0;

-- ============================================================
-- RESET: xóa audit entries từ lần chạy trước (idempotent)
-- ============================================================
TRUNCATE TABLE AuditLog;
SELECT 'AuditLog cleared.' AS Status;

-- ============================================================
-- TÌNH HUỐNG 1
-- Trip Singapore (TripID=4, đang ongoing) → completed
-- Expected: trg_after_trip_status_update đổi ContractID=4 → expired
--           trg_audit_contract_status ghi vào AuditLog
-- ============================================================
SELECT '--- BEFORE: Trip 4 status ---' AS Demo;
SELECT TripID, TripStatus FROM Trips WHERE TripID = 4;
SELECT ContractID, ContractStatus FROM Contracts WHERE TripID = 4;

UPDATE Trips SET TripStatus = 'completed' WHERE TripID = 4;

SELECT '--- AFTER: Contract auto-expired ---' AS Demo;
SELECT ContractID, ContractStatus FROM Contracts WHERE TripID = 4;

-- ============================================================
-- TÌNH HUỐNG 2 & 3
-- Duyệt Claim 5 (Cuong's Singapore baggage — đang under_review)
-- Expected: sp_ProcessAssessment INSERT Assessments
--           → trg_after_assessment_insert: UPDATE Claims + INSERT Payouts
--           → trg_audit_claim_status ghi ClaimStatus change
--           → trg_audit_payout_insert ghi Payout mới
-- ============================================================
SELECT '--- BEFORE: Claim 5 status ---' AS Demo;
SELECT ClaimID, ClaimStatus FROM Claims WHERE ClaimID = 5;
SELECT 'No payout yet:' AS Demo;
SELECT * FROM Payouts WHERE ClaimID = 5;

CALL sp_ProcessAssessment(
    5,
    'approved',
    3200000.00,
    'Singapore Airlines confirmed delayed baggage. Receipts submitted. Approved at 90% of declared value.'
);

SELECT '--- AFTER: Claim approved + Payout created ---' AS Demo;
SELECT ClaimID, ClaimStatus FROM Claims WHERE ClaimID = 5;
SELECT * FROM Payouts WHERE ClaimID = 5;

-- ============================================================
-- XEM TOÀN BỘ AUDIT LOG
-- Hiển thị: ai làm gì, bảng nào, từ status nào sang status nào, lúc mấy giờ
-- ============================================================
SELECT '--- AUDIT LOG: Full trail ---' AS Demo;
SELECT
    LogID,
    ChangedAt,
    DBUser,
    TableName,
    Action,
    RecordID,
    OldStatus,
    NewStatus,
    Note
FROM AuditLog
ORDER BY LogID;

-- ============================================================
-- ĐIỂM QUAN TRỌNG CẦN GIẢI THÍCH KHI DEMO:
--
-- 1. DBUser = 'tripAssure_admin@localhost'
--    → AuditLog tự động ghi CURRENT_USER() — không cần app truyền vào
--
-- 2. Claim status change (under_review → approved) được ghi
--    dù trigger trg_after_assessment_insert mới là thứ UPDATE Claims,
--    không phải người dùng trực tiếp
--    → Audit trail bắt được cả thay đổi gián tiếp qua trigger chain
--
-- 3. Payout INSERT cũng được ghi kèm ClaimID và Amount trong Note
--    → Có thể trace ngược: Payout nào → từ Claim nào → do ai approve
-- ============================================================

SET SQL_SAFE_UPDATES = 1;
