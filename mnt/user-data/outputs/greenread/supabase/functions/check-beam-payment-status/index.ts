// Supabase Edge Function: check-beam-payment-status
//
// ให้ผู้ใช้ (ที่ล็อกอินแล้ว) กดตรวจสอบสถานะออเดอร์ของตัวเองได้ทันที โดยยิงไปถาม Beam โดยตรง
// ใช้เป็นทางสำรองของปุ่ม "ฉันชำระเงินแล้ว" เผื่อ webhook (beam-webhook) ยังตั้งค่าไม่เสร็จหรือมาช้า
//
// หมายเหตุ: Beam ไม่มีสถานะ "หมดอายุ" อัตโนมัติ — charge ที่ผู้ใช้ไม่จ่ายจะค้างเป็น PENDING ตลอดไป
// ฟังก์ชันนี้จึงเช็คเวลาสร้างออเดอร์เอง ถ้าเกิน 15 นาทีแล้วยัง PENDING จะถือว่าหมดอายุ
//
// Deploy:
//   supabase functions deploy check-beam-payment-status
// ใช้ secrets เดียวกับ create-beam-charge (ตั้งไว้แล้วถ้า deploy ตัวนั้นไปก่อนหน้า):
//   BEAM_MERCHANT_ID, BEAM_API_KEY, BEAM_API_BASE_URL

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BEAM_MERCHANT_ID = Deno.env.get("BEAM_MERCHANT_ID") ?? "";
const BEAM_API_KEY = Deno.env.get("BEAM_API_KEY") ?? "";
const BEAM_API_BASE_URL = Deno.env.get("BEAM_API_BASE_URL") ?? "https://playground.api.beamcheckout.com";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const QR_TIMEOUT_MS = 15 * 60 * 1000; // ต้องตรงกับ expiryTime ที่ตั้งไว้ตอนสร้าง charge

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}

function beamAuthHeader(): string {
  return "Basic " + btoa(`${BEAM_MERCHANT_ID}:${BEAM_API_KEY}`);
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });

  try {
    if (!BEAM_MERCHANT_ID || !BEAM_API_KEY) {
      return json({ error: "ยังไม่ได้ตั้งค่า BEAM_MERCHANT_ID/BEAM_API_KEY บน Supabase" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) return json({ error: "ไม่พบ Authorization header — กรุณาเข้าสู่ระบบใหม่" }, 401);

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userErr } = await supabaseAdmin.auth.getUser(token);
    if (userErr || !userData?.user) return json({ error: "เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่" }, 401);
    const user = userData.user;

    const { order_id } = await req.json();
    if (!order_id) return json({ error: "ไม่พบ order_id" }, 400);

    const { data: order, error: orderErr } = await supabaseAdmin
      .from("orders")
      .select("id, user_id, status, charge_id, created_at")
      .eq("id", order_id)
      .single();

    if (orderErr || !order) return json({ error: "ไม่พบออเดอร์นี้" }, 404);
    if (order.user_id !== user.id) return json({ error: "ไม่มีสิทธิ์เข้าถึงออเดอร์นี้" }, 403);

    if (order.status === "paid") return json({ status: "paid" });
    if (!order.charge_id) return json({ status: "pending" });

    const verifyRes = await fetch(`${BEAM_API_BASE_URL}/api/v1/charges/${order.charge_id}`, {
      headers: { Authorization: beamAuthHeader() },
    });
    const charge = await verifyRes.json();
    if (!verifyRes.ok) return json({ error: "ตรวจสอบสถานะกับ Beam ไม่สำเร็จ", detail: charge }, 502);

    if (charge.status === "SUCCEEDED") {
      const { error: creditErr } = await supabaseAdmin.rpc("credit_order", { p_order_id: order.id });
      if (creditErr) return json({ error: "เติมเหรียญไม่สำเร็จ", detail: creditErr.message }, 500);
      return json({ status: "paid" });
    }

    if (charge.status === "FAILED") {
      await supabaseAdmin.from("orders").update({ status: "failed" }).eq("id", order.id);
      return json({ status: "failed", failureCode: charge.failureCode });
    }

    // ยัง PENDING — เช็คเองว่าเลยเวลาหมดอายุ QR แล้วหรือยัง (Beam ไม่มีสถานะ expired ให้)
    const createdAt = new Date(order.created_at).getTime();
    if (Date.now() - createdAt > QR_TIMEOUT_MS) {
      await supabaseAdmin.from("orders").update({ status: "expired" }).eq("id", order.id);
      return json({ status: "expired" });
    }

    return json({ status: "pending" });
  } catch (e) {
    return json({ error: "เกิดข้อผิดพลาดที่ไม่คาดคิด", detail: String(e) }, 500);
  }
});
