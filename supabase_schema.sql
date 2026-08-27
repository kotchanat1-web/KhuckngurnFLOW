-- ============================================================================
-- Khuckngurn Flow (กวักเงิน Flow) - Supabase Database Schema & Realtime Setup
-- ============================================================================
-- Copy and run this SQL script in Supabase Dashboard -> SQL Editor
-- ============================================================================

-- 1. Enable UUID Extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- 2. CUSTOMERS TABLE
CREATE TABLE IF NOT EXISTS public.customers (
    id TEXT PRIMARY KEY,
    code TEXT,
    name TEXT NOT NULL,
    phone TEXT,
    address TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. INVOICES TABLE
CREATE TABLE IF NOT EXISTS public.invoices (
    id TEXT PRIMARY KEY,
    iv_number TEXT NOT NULL UNIQUE,
    doc_type TEXT DEFAULT 'ใบส่งของชั่วคราว',
    customer_id TEXT,
    invoice_date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    delivery_vehicle TEXT,
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
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 4. PAYMENTS TABLE
CREATE TABLE IF NOT EXISTS public.payments (
    id TEXT PRIMARY KEY,
    payment_number TEXT NOT NULL UNIQUE,
    customer_id TEXT,
    payment_date DATE DEFAULT CURRENT_DATE,
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

-- 5. COMPANY BANK ACCOUNTS TABLE
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

-- 6. AUDIT LOGS TABLE
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

-- 7. APP STATE FULL BACKUP TABLE (Snapshot Sync)
CREATE TABLE IF NOT EXISTS public.app_state_backup (
    id TEXT PRIMARY KEY DEFAULT 'main_state',
    state_data JSONB NOT NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================================
-- 8. ROW LEVEL SECURITY (RLS) POLICIES (Public read & write for Anon Key)
-- ============================================================================

ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.company_bank_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_state_backup ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if any
DROP POLICY IF EXISTS "Public access for customers" ON public.customers;
DROP POLICY IF EXISTS "Public access for invoices" ON public.invoices;
DROP POLICY IF EXISTS "Public access for payments" ON public.payments;
DROP POLICY IF EXISTS "Public access for company_bank_accounts" ON public.company_bank_accounts;
DROP POLICY IF EXISTS "Public access for audit_logs" ON public.audit_logs;
DROP POLICY IF EXISTS "Public access for app_state_backup" ON public.app_state_backup;

-- Allow all operations for anon role
CREATE POLICY "Public access for customers" ON public.customers FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for invoices" ON public.invoices FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for payments" ON public.payments FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for company_bank_accounts" ON public.company_bank_accounts FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for audit_logs" ON public.audit_logs FOR ALL USING (true) WITH CHECK (true);
CREATE POLICY "Public access for app_state_backup" ON public.app_state_backup FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- 9. REALTIME REPLICATION (Instant Multi-Device Synchronization)
-- ============================================================================

-- Add all tables to supabase_realtime publication
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_publication WHERE pubname = 'supabase_realtime') THEN
        CREATE PUBLICATION supabase_realtime;
    END IF;
END $$;

ALTER PUBLICATION supabase_realtime ADD TABLE public.customers;
ALTER PUBLICATION supabase_realtime ADD TABLE public.invoices;
ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;
ALTER PUBLICATION supabase_realtime ADD TABLE public.company_bank_accounts;
ALTER PUBLICATION supabase_realtime ADD TABLE public.audit_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE public.app_state_backup;
