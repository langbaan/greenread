// Supabase Edge Function: beam-webhook
//
// ตั้งค่า URL นี้ใน Beam Lighthouse (https://lighthouse.beamcheckout.com) > Developers > Webhooks:
//   https://<YOUR_PROJECT_REF>.supabase.co/functions/v1/beam-webhook
//
// ต่างจาก Omise ตรงที่ Beam เซ็น payload ด้วย HMAC-SHA256 จริง (header X-Beam-Signature, เข้ารหัส base64)
// ฟังก์ชันนี้จึงตรวจสอบลายเซ็นก่อนเชื่อ payload ได้เลย (ปลอดภัยกว่า Omise ที่ไม่มีการเซ็น)
// อ้างอิง: https://docs.beamcheckout.com/webhook-authentication
//
// Deploy:
//   supabase functions deploy beam-webhook --no-verify-jwt
// (ต้องใส่ --no-verify-jwt เพราะ Beam ไม่ได้ส่ง Supabase JWT มาด้วย)
//
// ตั้งค่า secret ก่อน deploy (รันครั้งเดียว):
//   supabase secrets set BEAM_WEBHOOK_HMAC_KEY=xxxxxxxx (คีย์ base64 จาก Lighthouse หน้า Webhooks)

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const BEAM_WEBHOOK_HMAC_KEY = Deno.env.get("BEAM_WEBHOOK_HMAC_KEY") ?? "";
const SUPABASE_URL = Deno.env.get("SUPABASE_URL") ?? "";
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "";

function base64ToBytes(b64: string): Uint8Array {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes;
}

function bytesToBase64(bytes: ArrayBuffer): string {
  let bin = "";
  new Uint8Array(bytes).forEach((b) => (bin += String.fromCharCode(b)));
  return btoa(bin);
}

async function verifyBeamSignature(rawBody: string, signatureHeader: string): Promise<boolean> {
  if (!BEAM_WEBHOOK_HMAC_KEY || !signatureHeader) return false;
  const keyBytes = base64ToBytes(BEAM_WEBHOOK_HMAC_KEY);
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    keyBytes,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signatureBytes = await crypto.subtle.sign("HMAC", cryptoKey, new TextEncoder().encode(rawBody));
  const computedSignature = bytesToBase64(signatureBytes);
  return computedSignature === signatureHeader;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }

  try {
    // ⚠️ ต้องอ่านเป็น raw text ก่อน แล้วค่อย JSON.parse จาก string เดิม
    // ห้าม JSON.stringify(await req.json()) กลับไปเช็คลายเซ็น เพราะลำดับ key/ช่องว่างอาจไม่ตรงกับต้นฉบับ
    const rawBody = await req.text();
    const signature = req.headers.get("X-Beam-Signature") ?? "";

    const isValid = await verifyBeamSignature(rawBody, signature);
    if (!isValid) {
      console.error("beam-webhook: invalid signature");
      return new Response("invalid signature", { status: 401 });
    }

    const payload = JSON.parse(rawBody);
    const chargeId: string | undefined = payload?.chargeId;
    const status: string | undefined = payload?.status; // "SUCCEEDED" | "FAILED" | "PENDING"

    if (!chargeId) {
      // ตอบ 200 เสมอเพื่อไม่ให้ Beam คิดว่า endpoint พัง แล้วยิงซ้ำรัว ๆ (Beam retry สูงสุด 10 ครั้ง)
      return new Response("ignored: no charge id", { status: 200 });
    }

    const supabaseAdmin = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);

    const { data: order } = await supabaseAdmin
      .from("orders")
      .select("id, status")
      .eq("charge_id", chargeId)
      .single();

    if (!order) {
      return new Response("ignored: unknown order", { status: 200 });
    }
    if (order.status === "paid") {
      return new Response("ok: already paid", { status: 200 }); // idempotent กันเติมซ้ำ
    }

    if (status === "SUCCEEDED") {
      const { error: creditErr } = await supabaseAdmin.rpc("credit_order", { p_order_id: order.id });
      if (creditErr) {
        console.error("credit_order failed", creditErr);
        return new Response("error crediting order", { status: 500 });
      }
      return new Response("ok: credited", { status: 200 });
    }

    if (status === "FAILED") {
      await supabaseAdmin.from("orders").update({ status: "failed" }).eq("id", order.id);
      return new Response("ok: marked failed", { status: 200 });
    }

    // ยัง PENDING อยู่ — ไม่ต้องทำอะไร รอ event ถัดไป (Beam จะส่งมาอีกทีตอนถึงสถานะสุดท้าย)
    return new Response("ok: still pending", { status: 200 });
  } catch (e) {
    console.error("beam-webhook error", e);
    return new Response("error", { status: 500 });
  }
});
