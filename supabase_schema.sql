-- ============================================================================
-- Khuckngurn Flow (กวักเงิน Flow) - Complete Supabase Database Schema & Realtime Setup
-- ============================================================================
-- คำแนะนำ: คัดลอกคำสั่ง SQL ทั้งหมดนี้ไปวางใน Supabase Dashboard -> SQL Editor แล้วกด Run
-- ============================================================================

-- 1. Enable Extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. CUSTOMERS TABLE (ข้อมูลลูกค้า / ร้านค้า)
CREATE TABLE IF NOT EXISTS public.customers (
    id TEXT PRIMARY KEY,
    code TEXT,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. INVOICES TABLE (ข้อมูลบิลขาย / ใบส่งของชั่วคราว)
CREATE TABLE IF NOT EXISTS public.invoices (
    id TEXT PRIMARY KEY,
    iv_number TEXT NOT NULL UNIQUE,
    doc_type TEXT DEFAULT 'ใบส่งของชั่วคราว',
    customer_id TEXT,
    customer_name TEXT,
    invoice_date TEXT,
    due_date TEXT,
    delivery_vehicle TEXT,
    salesperson TEXT,
    total_amount NUMERIC(15, 2) DEFAULT 0.00,
    paid_amount NUMERIC(15, 2) DEFAULT 0.00,
    outstanding_amount NUMERIC(15, 2) DEFAULT 0.00,
    status TEXT DEFAULT 'UNPAID',
    items JSONB DEFAULT '[]'::jsonb,
    amount_text TEXT,
    raw_content TEXT,
    source_file TEXT,
    slip_data JSONB,
    approved_by TEXT,
    approved_at TEXT,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. PAYMENTS TABLE (ข้อมูลการรับชำระเงิน)
CREATE TABLE IF NOT EXISTS public.payments (
    id TEXT PRIMARY KEY,
    payment_number TEXT NOT NULL UNIQUE,
    customer_id TEXT,
    payment_date TEXT,
    payment_type TEXT DEFAULT 'TRANSFER',
    amount NUMERIC(15, 2) DEFAULT 0.00,
    matched_amount NUMERIC(15, 2) DEFAULT 0.00,
    unmatched_amount NUMERIC(15, 2) DEFAULT 0.00,
    reference_number TEXT,
    bank_account TEXT,
    note TEXT,
    slip_data JSONB,
    matched_invoices JSONB DEFAULT '[]'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 5. PAYMENT ALLOCATIONS TABLE (ข้อมูลการตัดยอดบิล)
CREATE TABLE IF NOT EXISTS public.payment_allocations (
    id TEXT PRIMARY KEY,
    payment_id TEXT,
    invoice_id TEXT,
    allocated_amount NUMERIC(15, 2) DEFAULT 0.00,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 6. COMPANY BANK ACCOUNTS TABLE (บัญชีธนาคารของบริษัท)
CREATE TABLE IF NOT EXISTS public.company_bank_accounts (
    id TEXT PRIMARY KEY,
    bank_code TEXT,
    bank_name TEXT,
    account_number TEXT,
    account_name TEXT,
    logo_file TEXT,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 7. AUDIT LOGS TABLE (ประวัติการใช้งานและกิจกรรม)
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id TEXT PRIMARY KEY,
    timestamp TEXT,
    user_name TEXT,
    action TEXT,
    table_name TEXT,
    record_id TEXT,
    detail TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- 8. APP STATE FULL BACKUP TABLE (Snapshot Database สำหรับ Sync ทุกเครื่องทันที)
CREATE TABLE IF NOT EXISTS public.app_state_backup (
    id TEXT PRIMARY KEY DEFAULT 'main_state',
    state_data JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 9. INDEXES FOR PERFORMANCE
-- ============================================================================
CREATE INDEX IF NOT EXISTS idx_invoices_iv_number ON public.invoices (iv_number);
CREATE INDEX IF NOT EXISTS idx_invoices_customer_id ON public.invoices (customer_id);
CREATE INDEX IF NOT EXISTS idx_invoices_status ON public.invoices (status);
CREATE INDEX IF NOT EXISTS idx_payments_payment_number ON public.payments (payment_number);
CREATE INDEX IF NOT EXISTS idx_payments_customer_id ON public.payments (customer_id);

-- ============================================================================
-- 10. ROW LEVEL SECURITY (RLS) POLICIES (Public read & write for Anon Key)
-- ============================================================================
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payment_allocations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_state_backup ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Public access for customers" ON public.customers;
DROP POLICY IF EXISTS "Public access for invoices" ON public.invoices;
DROP POLICY IF EXISTS "Public access for payments" ON public.payments;
DROP POLICY IF EXISTS "Public access for payment_allocations" ON public.payment_allocations;
DROP POLICY IF EXISTS "Public access for company_bank_accounts" ON public.company_bank_accounts;
DROP POLICY IF EXISTS "Public access for audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Public access for app_state_backup" ON public.app_state_backup;

-- Allow all operations for anon and authenticated roles
CREATE POLICY "Public access for customers" ON public.customers FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for invoices" ON public.invoices FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for payments" ON public.payments FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for payment_allocations" ON public.payment_allocations FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for company_bank_accounts" ON public.company_bank_accounts FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for audit_logs" ON public.audit_logs FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for app_state_backup" ON public.app_state_backup FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- 11. REPLICA IDENTITY FULL (For reliable realtime change payloads)
-- ============================================================================
ALTER TABLE public.customers REPLICA IDENTITY FULL;
ALTER TABLE public.invoices REPLICA IDENTITY FULL;
ALTER TABLE public.payments REPLICA IDENTITY FULL;
ALTER TABLE public.payment_allocations REPLICA IDENTITY FULL;
ALTER TABLE public.company_bank_accounts REPLICA IDENTITY FULL;
ALTER TABLE public.audit_logs REPLICA IDENTITY FULL;
ALTER TABLE public.app_state_backup REPLICA IDENTITY FULL;

-- ============================================================================
-- 12. REALTIME REPLICATION (Instant Multi-Device Synchronization)
-- ============================================================================
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.customers;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.invoices;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_allocations;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.company_bank_accounts;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.audit_logs;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;

    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.app_state_backup;
    EXCEPTION WHEN duplicate_object THEN NULL;
    END;
END $$;

-- ============================================================================
-- 13. STORAGE BUCKET SETUP (จัดเก็บภาพสลิป เช็ค และ Statement ถาวร)
-- ============================================================================
-- สร้าง Bucket ชื่อ 'proofs' (Public Bucket สำหรับเก็บไฟล์หลักฐานภาพ)
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
    'proofs', 
    'proofs', 
    true, 
    10485760, -- จำกัดขนาด 10MB ต่อไฟล์ (ระบบ Client บีบอัดเหลือ ~100KB อยู่แล้ว)
    ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE 
SET public = true, 
    file_size_limit = 10485760,
    allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp', 'application/pdf'];

-- RLS Policies สำหรับ storage.objects
-- ลบ Policy เดิมออกก่อนทั้งหมดเพื่อป้องกันข้อผิดพลาด "policy already exists"
DROP POLICY IF EXISTS "Public read access for proofs" ON storage.objects;
DROP POLICY IF EXISTS "Public insert access for proofs" ON storage.objects;
DROP POLICY IF EXISTS "Public update access for proofs" ON storage.objects;
DROP POLICY IF EXISTS "Public delete access for proofs" ON storage.objects;
DROP POLICY IF EXISTS "Public access for proofs" ON storage.objects;
DROP POLICY IF EXISTS "Allow public uploads to proofs" ON storage.objects;
DROP POLICY IF EXISTS "Allow public read from proofs" ON storage.objects;
DROP POLICY IF EXISTS "Allow public delete from proofs" ON storage.objects;

-- อนุญาตให้อัปโหลดไฟล์ ดูไฟล์ และจัดการไฟล์ใน bucket 'proofs' ได้อย่างสมบูรณ์
CREATE POLICY "Public read access for proofs" ON storage.objects
FOR SELECT USING (bucket_id = 'proofs');

CREATE POLICY "Public insert access for proofs" ON storage.objects
FOR INSERT WITH CHECK (bucket_id = 'proofs');

CREATE POLICY "Public update access for proofs" ON storage.objects
FOR UPDATE USING (bucket_id = 'proofs') WITH CHECK (bucket_id = 'proofs');

CREATE POLICY "Public delete access for proofs" ON storage.objects
FOR DELETE USING (bucket_id = 'proofs');
