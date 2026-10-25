-- ============================================================================
-- Khuckngurn Flow (กวักเงิน Flow) — SYNC V2 MIGRATION
-- รันใน Supabase Dashboard -> SQL Editor (รันซ้ำได้ ไม่ลบข้อมูลเดิม)
--
-- สิ่งที่ทำ:
--   1) เพิ่มคอลัมน์ data / deleted_at / server_updated_at ให้ทุกตาราง
--   2) เวลาแก้ไขฝั่ง Server (trigger) ใช้ดึงข้อมูลเฉพาะส่วนที่เปลี่ยน
--   3) ฟังก์ชัน kf_upsert: เขียนทีละแถว ไม่ทับข้อมูลที่ใหม่กว่า และแจ้ง error รายแถว
--   4) ฟังก์ชัน kf_soft_delete: ลบแบบมีร่องรอย (เครื่องอื่นรู้ว่าถูกลบ)
--   5) ตาราง app_settings (พนักงาน / บัญชีธนาคาร / PIN)
--   6) ปิดการเขียน snapshot ก้อนใหญ่ (app_state_backup) — กันเครื่องที่ยังใช้โค้ดเก่าเขียนทับ
--      (ข้อมูลใน snapshot ยังอยู่ครบ โปรแกรมใหม่จะอ่านไปรวมให้อัตโนมัติ 1 ครั้ง)
-- ============================================================================

-- 1. COLUMNS ------------------------------------------------------------------
DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['customers','invoices','payments','payment_allocations','audit_logs'] LOOP
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS data jsonb', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS deleted_at timestamptz', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS updated_at timestamptz DEFAULT now()', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS created_at timestamptz DEFAULT now()', t);
    EXECUTE format('ALTER TABLE public.%I ADD COLUMN IF NOT EXISTS server_updated_at timestamptz DEFAULT now()', t);
    EXECUTE format('CREATE INDEX IF NOT EXISTS %I ON public.%I (server_updated_at)', 'idx_' || t || '_server_updated_at', t);
  END LOOP;
END $$;

-- เลขใบรับเงินเดิมเคยซ้ำกันข้ามเครื่อง -> ยกเลิก UNIQUE (ยังมี index ค้นหาอยู่)
ALTER TABLE public.payments DROP CONSTRAINT IF EXISTS payments_payment_number_key;

-- 2. SETTINGS TABLE -------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_settings (
  id TEXT PRIMARY KEY,
  data JSONB,
  updated_at TIMESTAMPTZ DEFAULT now(),
  created_at TIMESTAMPTZ DEFAULT now(),
  deleted_at TIMESTAMPTZ,
  server_updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_app_settings_server_updated_at ON public.app_settings (server_updated_at);
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Public access for app_settings" ON public.app_settings;
CREATE POLICY "Public access for app_settings" ON public.app_settings FOR ALL USING (true) WITH CHECK (true);

-- 3. SERVER TIMESTAMP TRIGGER ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.kf_touch() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.server_updated_at := clock_timestamp();
  IF TG_OP = 'INSERT' THEN
    NEW.created_at := COALESCE(NEW.created_at, now());
  ELSE
    NEW.created_at := OLD.created_at;
  END IF;
  RETURN NEW;
END $$;

DO $$
DECLARE t text;
BEGIN
  FOREACH t IN ARRAY ARRAY['customers','invoices','payments','payment_allocations','audit_logs','app_settings'] LOOP
    EXECUTE format('DROP TRIGGER IF EXISTS kf_touch_trg ON public.%I', t);
    EXECUTE format('CREATE TRIGGER kf_touch_trg BEFORE INSERT OR UPDATE ON public.%I FOR EACH ROW EXECUTE FUNCTION public.kf_touch()', t);
    -- ลดขนาด WAL: ไม่ต้องเก็บแถวเก่าทั้งแถวในทุกการแก้ไข
    EXECUTE format('ALTER TABLE public.%I REPLICA IDENTITY DEFAULT', t);
  END LOOP;
END $$;

-- 4. SAFE ROW UPSERT ---------------------------------------------------------------
-- p_rows : jsonb array ของแถว (key = ชื่อคอลัมน์)
-- p_key  : คอลัมน์ที่ใช้ยืนยันว่าเป็น "รายการเดียวกัน" (เช่น iv_number) กันรหัสชนกันข้ามเครื่อง
-- คืนค่า : {applied:[id], stale:[id], collided:[id], errors:[{id,error}]}
--   stale    = บน Cloud มีฉบับที่ใหม่กว่า (ไม่เขียนทับ)
--   collided = id เดียวกันแต่เป็นคนละรายการ (ไม่เขียนทับ)
CREATE OR REPLACE FUNCTION public.kf_upsert(p_table text, p_rows jsonb, p_key text[] DEFAULT NULL)
RETURNS jsonb LANGUAGE plpgsql AS $$
DECLARE
  r jsonb; v_id text; v_cols text; v_set text; v_keycond text := ''; v_keycmp text; n int;
  v_same boolean; v_found boolean; k text;
  applied text[] := '{}'; stale text[] := '{}'; collided text[] := '{}'; errs jsonb := '[]'::jsonb;
BEGIN
  IF p_table NOT IN ('customers','invoices','payments','payment_allocations','audit_logs','app_settings') THEN
    RAISE EXCEPTION 'kf_upsert: table % not allowed', p_table;
  END IF;

  SELECT string_agg(quote_ident(column_name), ',' ORDER BY ordinal_position),
         string_agg(format('%1$I = EXCLUDED.%1$I', column_name), ',' ORDER BY ordinal_position)
           FILTER (WHERE column_name NOT IN ('id','created_at','deleted_at'))
    INTO v_cols, v_set
    FROM information_schema.columns
   WHERE table_schema = 'public' AND table_name = p_table AND column_name <> 'server_updated_at';

  IF p_key IS NOT NULL AND array_length(p_key, 1) > 0 THEN
    FOREACH k IN ARRAY p_key LOOP
      v_keycond := v_keycond || format(' AND public.%1$I.%2$I IS NOT DISTINCT FROM EXCLUDED.%2$I', p_table, k);
    END LOOP;
    SELECT string_agg(format('t.%1$I::text IS NOT DISTINCT FROM ($2->>%1$L)', kk), ' AND ')
      INTO v_keycmp FROM unnest(p_key) kk;
  END IF;

  FOR r IN SELECT * FROM jsonb_array_elements(COALESCE(p_rows, '[]'::jsonb)) LOOP
    v_id := r->>'id';
    IF v_id IS NULL OR v_id = '' THEN
      errs := errs || jsonb_build_object('id', NULL, 'error', 'missing id');
      CONTINUE;
    END IF;
    BEGIN
      EXECUTE format(
        'INSERT INTO public.%1$I (%2$s) SELECT %2$s FROM jsonb_populate_record(NULL::public.%1$I, $1) '
        'ON CONFLICT (id) DO UPDATE SET %3$s '
        'WHERE (public.%1$I.updated_at IS NULL OR EXCLUDED.updated_at IS NULL OR public.%1$I.updated_at <= EXCLUDED.updated_at)%4$s',
        p_table, v_cols, v_set, v_keycond) USING r;
      GET DIAGNOSTICS n = ROW_COUNT;
      IF n > 0 THEN
        applied := applied || v_id;
      ELSIF v_keycmp IS NOT NULL THEN
        EXECUTE format('SELECT true, (%s) FROM public.%I t WHERE t.id = $1', v_keycmp, p_table)
          INTO v_found, v_same USING v_id, r;
        IF v_found AND NOT COALESCE(v_same, false) THEN
          collided := collided || v_id;
        ELSE
          stale := stale || v_id;
        END IF;
      ELSE
        stale := stale || v_id;
      END IF;
    EXCEPTION WHEN OTHERS THEN
      errs := errs || jsonb_build_object('id', v_id, 'error', SQLERRM);
    END;
  END LOOP;

  RETURN jsonb_build_object('applied', to_jsonb(applied), 'stale', to_jsonb(stale),
                            'collided', to_jsonb(collided), 'errors', errs);
END $$;

-- 5. SOFT DELETE -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.kf_soft_delete(p_table text, p_ids text[])
RETURNS int LANGUAGE plpgsql AS $$
DECLARE n int;
BEGIN
  IF p_table NOT IN ('customers','invoices','payments','payment_allocations','audit_logs','app_settings') THEN
    RAISE EXCEPTION 'kf_soft_delete: table % not allowed', p_table;
  END IF;
  EXECUTE format('UPDATE public.%I SET deleted_at = now(), updated_at = now() WHERE id = ANY($1) AND deleted_at IS NULL', p_table)
    USING p_ids;
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN n;
END $$;

GRANT EXECUTE ON FUNCTION public.kf_upsert(text, jsonb, text[]) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.kf_soft_delete(text, text[]) TO anon, authenticated;
GRANT ALL ON public.app_settings TO anon, authenticated;

-- 6. BLOCK OLD SNAPSHOT WRITES ---------------------------------------------------
-- เครื่องที่ยังเปิดโปรแกรมเวอร์ชันเก่าจะบันทึกขึ้น Cloud ไม่ได้ (ข้อมูลยังอยู่ในเครื่อง)
-- พอรีเฟรชเป็นเวอร์ชันใหม่ ข้อมูลจะถูกส่งขึ้นแบบปลอดภัยเอง
CREATE OR REPLACE FUNCTION public.kf_block_snapshot() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'KF_SYNC_V2: ระบบอัปเดตเป็น Sync v2 แล้ว กรุณารีเฟรชหน้าเว็บ (Ctrl+F5)';
END $$;
DROP TRIGGER IF EXISTS kf_block_snapshot_trg ON public.app_state_backup;
CREATE TRIGGER kf_block_snapshot_trg BEFORE INSERT OR UPDATE ON public.app_state_backup
  FOR EACH ROW EXECUTE FUNCTION public.kf_block_snapshot();

-- 7. REALTIME PUBLICATION ---------------------------------------------------------
DO $$
BEGIN
  BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.app_state_backup; EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime DROP TABLE public.audit_logs;       EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.app_settings;      EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.customers;         EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.invoices;          EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.payments;          EXCEPTION WHEN OTHERS THEN NULL; END;
  BEGIN ALTER PUBLICATION supabase_realtime ADD TABLE public.payment_allocations; EXCEPTION WHEN OTHERS THEN NULL; END;
END $$;

-- 8. STORAGE BUCKET 'proofs' (เก็บรูปสลิปเป็นไฟล์ ไม่เก็บในฐานข้อมูล) ------------------------
DO $$
BEGIN
  IF to_regclass('storage.buckets') IS NOT NULL THEN
    EXECUTE $q$INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
      VALUES ('proofs', 'proofs', true, 10485760, ARRAY['image/jpeg','image/png','image/webp','application/pdf'])
      ON CONFLICT (id) DO UPDATE SET public = true, file_size_limit = 10485760,
        allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp','application/pdf']$q$;
    EXECUTE 'DROP POLICY IF EXISTS "Public read access for proofs" ON storage.objects';
    EXECUTE 'DROP POLICY IF EXISTS "Public insert access for proofs" ON storage.objects';
    EXECUTE 'DROP POLICY IF EXISTS "Public update access for proofs" ON storage.objects';
    EXECUTE $q$CREATE POLICY "Public read access for proofs" ON storage.objects FOR SELECT USING (bucket_id = 'proofs')$q$;
    EXECUTE $q$CREATE POLICY "Public insert access for proofs" ON storage.objects FOR INSERT WITH CHECK (bucket_id = 'proofs')$q$;
    EXECUTE $q$CREATE POLICY "Public update access for proofs" ON storage.objects FOR UPDATE USING (bucket_id = 'proofs') WITH CHECK (bucket_id = 'proofs')$q$;
  END IF;
END $$;

NOTIFY pgrst, 'reload schema';

-- ตรวจผล: ต้องเห็น 6 ตารางและคอลัมน์ server_updated_at
SELECT table_name, count(*) FILTER (WHERE column_name = 'server_updated_at') AS has_server_ts
  FROM information_schema.columns
 WHERE table_schema = 'public'
   AND table_name IN ('customers','invoices','payments','payment_allocations','audit_logs','app_settings')
 GROUP BY table_name ORDER BY table_name;
