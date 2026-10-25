-- ============================================================================
-- Khuckngurn Flow — เคลียร์พื้นที่ฐานข้อมูล Supabase
-- รันใน Supabase SQL Editor ทีละส่วน (คำสั่ง VACUUM ต้องรันทีละบรรทัด: เลือกบรรทัด แล้วกด Run)
-- ============================================================================

-- ---------------------------------------------------------------------------
-- ส่วนที่ 0: ดูขนาดปัจจุบัน
-- ---------------------------------------------------------------------------
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size;
SELECT relname, pg_size_pretty(pg_total_relation_size(relid)) AS total, n_live_tup, n_dead_tup
  FROM pg_stat_user_tables ORDER BY pg_total_relation_size(relid) DESC;

-- ---------------------------------------------------------------------------
-- ส่วนที่ 1: ถ้าฐานข้อมูลเต็มจนเป็น "อ่านอย่างเดียว" (error: read-only transaction)
-- ทำก่อนรัน supabase_sync_v2.sql — คืนพื้นที่จากข้อมูลเวอร์ชันเก่าที่ค้าง (ไม่ลบข้อมูลจริง)
-- ---------------------------------------------------------------------------
SET SESSION CHARACTERISTICS AS TRANSACTION READ WRITE;
VACUUM FULL public.app_state_backup;
VACUUM FULL public.invoices;
VACUUM FULL public.payments;
VACUUM FULL public.payment_allocations;
VACUUM FULL public.audit_logs;
SET default_transaction_read_only = 'off';
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size_after;

-- ---------------------------------------------------------------------------
-- ส่วนที่ 2: ทำหลังจากใช้ Sync v2 แล้ว 1–2 วัน และตรวจว่าทุกเครื่องเห็นข้อมูลครบ
-- เก็บ snapshot ก้อนเก่า (ข้อมูลอยู่ในตารางครบแล้ว) แล้วคืนพื้นที่
-- *** ก่อนรัน: กด "ดาวน์โหลดไฟล์สำรองข้อมูล" ในโปรแกรมเก็บไว้ 1 ชุด ***
-- ---------------------------------------------------------------------------
ALTER TABLE public.app_state_backup DISABLE TRIGGER kf_block_snapshot_trg;
UPDATE public.app_state_backup
   SET state_data = jsonb_build_object('archived_at', now(), 'note', 'ย้ายข้อมูลไปตารางแล้ว (Sync v2)')
 WHERE id = 'main_state';
ALTER TABLE public.app_state_backup ENABLE TRIGGER kf_block_snapshot_trg;
VACUUM FULL public.app_state_backup;
VACUUM FULL public.invoices;
VACUUM FULL public.payments;
SELECT pg_size_pretty(pg_database_size(current_database())) AS db_size_final;

-- ตรวจว่าไม่มีรูปสลิป base64 ค้างในฐานข้อมูลแล้ว (ควรเป็น 0 หลังทุกเครื่องเปิดโปรแกรมใหม่)
SELECT
  (SELECT count(*) FROM public.payments WHERE slip_data::text LIKE '%data:image%') AS payments_base64,
  (SELECT count(*) FROM public.invoices WHERE slip_data::text LIKE '%data:image%') AS invoices_base64;
