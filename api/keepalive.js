// Vercel Cron: แตะฐานข้อมูล Supabase วันละครั้ง กันโปรเจกต์ฟรีถูกพัก (pause) ช่วงวันหยุดยาว
// ใช้ publishable key ตัวเดียวกับที่อยู่ใน index.html (ไม่ใช่ความลับเพิ่ม)
module.exports = async (req, res) => {
  const url = process.env.SUPABASE_URL || 'https://fccnkzdjkeboaxvlvyyx.supabase.co';
  const key = process.env.SUPABASE_ANON_KEY || 'sb_publishable_LtxfObbyLtyBpiQaDBOmcg_HGP58G4i';
  try {
    const r = await fetch(url + '/rest/v1/invoices?select=id&limit=1', { headers: { apikey: key } });
    res.status(r.ok ? 200 : 502).json({ ok: r.ok, status: r.status, at: new Date().toISOString() });
  } catch (e) {
    res.status(500).json({ ok: false, error: String(e && e.message || e) });
  }
};
