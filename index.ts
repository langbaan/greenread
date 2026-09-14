// Supabase Edge Function: create-beam-charge
//
// รับ package_id จากผู้ใช้ที่ล็อกอินแล้ว -> สร้างออเดอร์ (pending) ในตาราง orders
// -> เรียก Beam Checkout API สร้าง QR PromptPay charge -> คืน QR image (base64) + order id กลับไปให้หน้าเว็บ
//
// อ้างอิงจาก Beam API Docs: https://docs.beamcheckout.com/charges/charges-api
//
// Deploy:
//   supabase functions deploy create-beam-charge
// ตั้งค่า secrets ก่อน deploy ครั้งแรก (รันครั้งเดียว):
//   supabase secrets set BEAM_MERCHANT_ID=m_xxxxxxxx
//   supabase secrets set BEAM_API_KEY=xxxxxxxxxxxxxxxx
//   supabase secrets set BEAM_API_BASE_URL=https://playground.api.beamcheckout.com
//     (โหมดทดสอบ — พอพร้อมใช้จริงค่อยเปลี่ยนเป็น https://api.beamcheckout.com)
//
// SUPABASE_URL และ SUPABASE_SERVICE_ROLE_KEY มีให้อัตโนมัติใน edge function runtime อยู่แล้ว ไม่ต้อง set เอง

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BEAM_MERCHANT_ID = Deno.env.get("BEAM_MERCHANT_ID") ?? "";
const BEAM_API_KEY = Deno.env.get("BEAM_API_KEY") ?? "";
// ค่าเริ่มต้นเป็น Playground (sandbox) เพื่อความปลอดภัย ป้องกันเผลอตัดเงินจริงตอนยังทดสอบอยู่
const BEAM_API_BASE_URL = Deno.env.get("BEAM_API_BASE_URL") ?? "https://playground.api.beamcheckout.com";
// ใช้เป็นค่า returnUrl ที่ Beam API ต้องการ (ฟิลด์บังคับ แต่ QR PromptPay ไม่ได้ใช้ redirect จริง)
const BEAM_RETURN_URL = Deno.env.get("BEAM_RETURN_URL") ?? "https://www.beamcheckout.com";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

const corsHeaders = {
  "Access-Control-Allow-Origin": "https://langbaan.store",
  "Access-Control-Allow-Headers": "authorization, x-client-info, x-supabase-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Max-Age": "86400",
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
      return json({ error: "ยังไม่ได้ตั้งค่า BEAM_MERCHANT_ID/BEAM_API_KEY บน Supabase (supabase secrets set)" }, 500);
    }

    const authHeader = req.headers.get("Authorization");
    if (!authHeader) {
      return json({ error: "ไม่พบ Authorization header — กรุณาเข้าสู่ระบบใหม่" }, 401);
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const token = authHeader.replace("Bearer ", "");
    const { data: userData, error: userErr } = await supabaseAdmin.auth.getUser(token);
    if (userErr || !userData?.user) {
      return json({ error: "เซสชันหมดอายุ กรุณาเข้าสู่ระบบใหม่" }, 401);
    }
    const user = userData.user;

    const { package_id } = await req.json();
    if (!package_id) return json({ error: "ไม่พบ package_id" }, 400);

    const { data: pkg, error: pkgErr } = await supabaseAdmin
      .from("coin_packages")
      .select("id, coins, price, bonus, active")
      .eq("id", package_id)
      .single();

    if (pkgErr || !pkg) return json({ error: "ไม่พบแพ็กเกจเหรียญนี้" }, 404);
    if (!pkg.active) return json({ error: "แพ็กเกจนี้ปิดขายอยู่" }, 400);

    // สร้างแถวออเดอร์ก่อน (pending) เพื่อกันข้อมูลหาย ถ้าเรียก Beam ล้มเหลวก็ยังเห็น record
    const { data: order, error: orderErr } = await supabaseAdmin
      .from("orders")
      .insert({
        user_id: user.id,
        package_id: pkg.id,
        coins: pkg.coins,
        bonus: pkg.bonus ?? 0,
        amount: pkg.price,
        status: "pending",
      })
      .select()
      .single();

    if (orderErr || !order) return json({ error: "สร้างออเดอร์ไม่สำเร็จ", detail: orderErr?.message }, 500);

    // จำนวนเงินของ Beam เป็นหน่วยสตางค์ (satang) เหมือนกัน = บาท * 100
    const amountSatang = Math.round(Number(pkg.price) * 100);
    // ให้ QR หมดอายุใน 15 นาที (Beam ไม่มีสถานะหมดอายุอัตโนมัติ ต้องกำหนดเองตรงนี้)
    const expiryTime = new Date(Date.now() + 15 * 60 * 1000).toISOString();

    const beamRes = await fetch(`${BEAM_API_BASE_URL}/api/v1/charges`, {
      method: "POST",
      headers: {
        Authorization: beamAuthHeader(),
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        amount: amountSatang,
        currency: "THB",
        paymentMethod: {
          qrPromptPay: { expiryTime },
          paymentMethodType: "QR_PROMPT_PAY",
        },
        // ใส่ prefix "greenread_" ไว้เสมอ เพื่อแยกรายการของเว็บนี้ออกจากเว็บอื่นที่อาจใช้บัญชี Beam เดียวกัน
        // กรองดูใน Lighthouse หรือ GET /api/v1/charges?referenceId=... ได้ทันที (ใช้ underscore กัน
        // ปัญหา URL-encoding ของอักขระพิเศษตอนกรองผ่าน query string)
        referenceId: `greenread_${order.id}`,
        returnUrl: BEAM_RETURN_URL,
        skip3dsFlow: false,
      }),
    });

    const charge = await beamRes.json();

    if (!beamRes.ok) {
      await supabaseAdmin.from("orders").update({ status: "failed" }).eq("id", order.id);
      return json({ error: "Beam ปฏิเสธการสร้างรายการชำระเงิน", detail: charge?.message || charge }, 502);
    }

    // actionRequired ควรเป็น "ENCODED_IMAGE" สำหรับ QR PromptPay เสมอ
    const imageBase64: string | undefined = charge?.encodedImage?.imageBase64Encoded;
    const qrImageUri = imageBase64 ? `data:image/png;base64,${imageBase64}` : null;

    await supabaseAdmin
      .from("orders")
      .update({ charge_id: charge.chargeId, qr_image_uri: qrImageUri })
      .eq("id", order.id);

    return json({
      orderId: order.id,
      chargeId: charge.chargeId,
      amount: pkg.price,
      coins: pkg.coins,
      bonus: pkg.bonus ?? 0,
      qrImageUri,
      expiry: charge?.encodedImage?.expiry ?? expiryTime,
    });
  } catch (e) {
    return json({ error: "เกิดข้อผิดพลาดที่ไม่คาดคิด", detail: String(e) }, 500);
  }
});
