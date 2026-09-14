# คู่มือติดตั้ง "นิยายหลังบ้าน" ฉบับสมบูรณ์
### สำหรับคนไม่เคยทำเว็บ ไม่เคยเขียนโค้ดมาก่อนเลย

คู่มือนี้จะพาไปทีละคลิก ตั้งแต่ศูนย์จนเว็บใช้งานได้จริง มีระบบสมาชิก จ่ายเงินจริงผ่าน PromptPay
และมีหน้าแอดมินจัดการนิยาย ใช้เวลาทำทั้งหมดประมาณ 45–90 นาที (ถ้าไม่มีปัญหาติดขัด)

**อ่านก่อนเริ่ม:** ทำตามลำดับข้อ 1 → 8 ห้ามข้าม แต่ละข้อจะบอกชัดเจนว่า "ทำที่ไหน" และ "ทำอะไร"
ถ้าติดตรงไหน มีหัวข้อ **"แก้ปัญหาที่พบบ่อย"** อยู่ท้ายไฟล์นี้

---

## ภาพรวม: เรากำลังต่ออะไรเข้ากับอะไร

ระบบนี้ประกอบด้วย 4 ส่วนที่ต้องเชื่อมกัน:

| ส่วน | ทำหน้าที่อะไร | ฟรีไหม |
|---|---|---|
| **Supabase** | ฐานข้อมูล + ระบบสมาชิก (ล็อกอิน/สมัคร) | ฟรี (แผน Free เพียงพอ) |
| **Beam Checkout** | รับเงินจริงผ่าน PromptPay QR | ฟรี ไม่มีค่าธรรมเนียม PromptPay |
| **GitHub** | เก็บไฟล์เว็บไซต์ | ฟรี |
| **Cloudflare Pages** | โฮสต์เว็บให้คนเข้าชมได้จริง | ฟรี |

ไฟล์ที่ต้องใช้ทั้งหมด (ควรดาวน์โหลดมาเก็บไว้ในโฟลเดอร์เดียวกันก่อน เช่นสร้างโฟลเดอร์ชื่อ `greenread` ที่ Desktop):

```
greenread/
├── index.html                                          ← หน้าเว็บทั้งหมด
└── supabase/
    ├── setup.sql                                       ← สร้างฐานข้อมูล
    └── functions/
        ├── create-beam-charge/index.ts                 ← สร้าง QR ชำระเงิน
        ├── beam-webhook/index.ts                        ← รับผลชำระเงิน
        └── check-beam-payment-status/index.ts           ← เช็คสถานะสำรอง
```

---

## ขั้นตอนที่ 1: สร้างโปรเจกต์ Supabase (ฐานข้อมูล)

### 1.1 สมัคร/เข้าสู่ระบบ Supabase

1. เปิดเบราว์เซอร์ไปที่ **https://supabase.com**
2. กด **Start your project** หรือ **Sign in** (มุมขวาบน)
3. สมัครด้วย GitHub หรืออีเมลก็ได้ ฟรี ไม่ต้องผูกบัตรเครดิต

### 1.2 สร้างโปรเจกต์ใหม่ (ข้ามได้ถ้ามีโปรเจกต์อยู่แล้ว)

1. กด **New Project**
2. เลือก Organization (ถ้าเพิ่งสมัครจะมีให้เลือกอันเดียว)
3. ตั้งชื่อโปรเจกต์ เช่น `greenread`
4. ตั้งรหัสผ่านฐานข้อมูล (Database Password) — **จดเก็บไว้ให้ดี** จะใช้ตอนหลัง
5. เลือก Region ใกล้ที่สุด (เช่น Southeast Asia (Singapore))
6. กด **Create new project** รอประมาณ 1-2 นาที

### 1.3 จำ Project Reference ของคุณไว้

ดูที่ URL ด้านบนเบราว์เซอร์ จะเป็นรูปแบบ:
```
supabase.com/dashboard/project/xxxxxxxxxxxxxxxxxxxx
```
ตัว `xxxxxxxxxxxxxxxxxxxx` (ยาวประมาณ 20 ตัวอักษร) คือ **Project Reference** ของคุณ
**คัดลอกเก็บไว้ในโน้ต** เพราะต้องใช้อ้างอิงหลายรอบต่อจากนี้

> ⚠️ ถ้ามีหลายโปรเจกต์ Supabase อยู่ ให้เช็คว่ากำลังทำงานอยู่ในโปรเจกต์นี้ทุกครั้ง (ดู URL ทุกครั้งก่อนทำขั้นตอนถัดไป)

### 1.4 รันไฟล์ setup.sql

1. เมนูซ้ายมือ มองหาไอคอน **SQL Editor** (รูปคล้ายเทอร์มินัล) กดเข้าไป
2. กด **New query** (ปุ่มมุมบน)
3. เปิดไฟล์ `supabase/setup.sql` ที่ดาวน์โหลดไว้ด้วยโปรแกรมข้อความ (Notepad, TextEdit, VS Code ก็ได้)
4. กด **Ctrl+A** (Windows) หรือ **Cmd+A** (Mac) เพื่อเลือกทั้งหมด แล้ว **Ctrl+C / Cmd+C** เพื่อคัดลอก
5. กลับมาที่หน้า SQL Editor ในเบราว์เซอร์ คลิกในช่องแก้ไขโค้ด กด **Ctrl+V / Cmd+V** วาง
6. กดปุ่ม **Run** (หรือ Ctrl+Enter) มุมขวาบนของกล่องโค้ด
7. รอสักครู่ ด้านล่างควรขึ้นว่า **Success. No rows returned**

**ถ้าขึ้น error สีแดง** ให้อ่านข้อความ error แล้วดูหัวข้อ "แก้ปัญหาที่พบบ่อย" ท้ายไฟล์นี้

### 1.5 ตรวจว่าตารางถูกสร้างจริง

1. เมนูซ้ายมือ กด **Table Editor**
2. ควรเห็นรายชื่อตารางทางซ้าย: `profiles`, `novels`, `chapters`, `coin_packages`, `liked_novels`,
   `purchased_chapters`, `orders`
3. กดเข้า `novels` ควรเห็นข้อมูลนิยาย 5 เรื่องอยู่แล้ว (เป็นข้อมูลตัวอย่างที่ผมใส่ไว้ให้ทดสอบ)

ถ้าเห็นครบตามนี้ **ขั้นตอนที่ 1 เสร็จสมบูรณ์** ✅

---

## ขั้นตอนที่ 2: เอาค่า SUPABASE_URL และ ANON_KEY มาใส่ในเว็บ

1. เมนูซ้ายมือ กดไอคอนรูปเฟือง **Project Settings** (อยู่ล่างสุด)
2. กดเมนูย่อย **API**
3. จะเห็น 2 ค่าที่ต้องใช้:
   - **Project URL** — หน้าตาแบบ `https://xxxxxxxxxxxxxxxxxxxx.supabase.co`
   - **Project API keys** → หาแถวที่เขียนว่า **`anon` `public`** (เป็นคีย์ยาวๆ ขึ้นต้นด้วย `eyJ...`)
4. คัดลอกทั้งสองค่าเก็บไว้ในโน้ต

### เอาไปใส่ในไฟล์ index.html

1. เปิดไฟล์ `index.html` ด้วยโปรแกรมข้อความ (Notepad / TextEdit / VS Code)
2. กด **Ctrl+F / Cmd+F** ค้นหาคำว่า `SUPABASE_URL`
3. จะเจอบรรทัดประมาณนี้:
   ```js
   const SUPABASE_URL = 'https://YOUR-PROJECT-REF.supabase.co';
   const SUPABASE_ANON_KEY = 'YOUR_SUPABASE_ANON_KEY';
   ```
4. แก้ให้เป็นค่าจริงของคุณ (ต้องอยู่ในเครื่องหมาย `'...'` เหมือนเดิม) เช่น:
   ```js
   const SUPABASE_URL = 'https://xxxxxxxxxxxxxxxxxxxx.supabase.co';
   const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...';
   ```
5. บันทึกไฟล์ (Ctrl+S / Cmd+S) — **ต้องบันทึกเป็น .html เหมือนเดิม** ไม่ใช่ .txt

> ⚠️ ห้ามใช้คีย์ที่ชื่อ `service_role` เด็ดขาดในไฟล์นี้ ใช้แค่คีย์ `anon` `public` เท่านั้น

---

## ขั้นตอนที่ 3: สมัคร Beam Checkout และเอาคีย์มา

### 3.1 สมัครบัญชี Beam

1. ไปที่ **https://lighthouse.beamcheckout.com**
2. สมัครสมาชิกด้วยอีเมล/เบอร์โทรศัพท์ (ไม่ต้องรออนุมัติเอกสารบริษัทถ้าจะใช้แค่โหมดทดสอบ Playground ก่อน)

### 3.2 เอา Merchant ID และ API Key

1. หลังล็อกอิน มองหาเมนูด้านขวามือ (หรือด้านข้าง) คำว่า **Developers** กดเข้าไป
2. เลือกโหมด **Playground / Sandbox** (มุมใดมุมหนึ่งของหน้าจอ มักมีตัวสลับ Production/Playground)
3. จะเห็น:
   - **Merchant ID** ขึ้นต้นด้วย `m_`
   - **API Key** เป็นรหัสยาวๆ
4. ถ้าไม่เห็น API Key หรือว่างเปล่า ให้มองหาปุ่ม **Generate** หรือ **Create API Key**
5. คัดลอกทั้งสองค่าเก็บไว้ในโน้ต

### 3.3 เอา Webhook HMAC Key

1. หน้าเดียวกัน (Developers) มองหาส่วน **Webhook Settings**
2. กด **Create Webhook**
3. ช่อง URL **ยังไม่ต้องกรอกตอนนี้** (จะกลับมากรอกในขั้นตอนที่ 5)
4. ระบบจะให้ **Webhook HMAC Key** มาด้วย — คัดลอกเก็บไว้ในโน้ต

ตอนนี้คุณควรมี 3 ค่าจาก Beam เก็บไว้ในโน้ตแล้ว: **Merchant ID**, **API Key**, **Webhook HMAC Key**

---

## ขั้นตอนที่ 4: Deploy Edge Functions (ตัวเชื่อมระหว่างเว็บกับ Beam)

Edge Function คือโค้ดเล็กๆ ที่ทำงานอยู่บนเซิร์ฟเวอร์ของ Supabase (ไม่ใช่ในเบราว์เซอร์ของผู้ใช้)
มีหน้าที่คุยกับ Beam อย่างปลอดภัย (เพราะต้องใช้ API Key ลับที่ห้ามฝังในหน้าเว็บ)

**วิธีนี้ทำผ่านเว็บเบราว์เซอร์ล้วนๆ ไม่ต้องติดตั้งโปรแกรมอะไรเพิ่ม ไม่ต้องใช้ Command Prompt/Terminal**

### 4.1 ตั้งค่า Secrets ก่อน (ค่าลับที่ Edge Function จะใช้)

1. ใน Supabase Dashboard เมนูซ้าย กด **Edge Functions**
2. มองหาแท็บหรือเมนู **Secrets** / **Manage secrets** (มักอยู่ในหน้าเดียวกันหรือใต้ Settings ของ Edge Functions)
3. เพิ่ม secrets ทีละตัว (ชื่อ = ค่า):

   | ชื่อ (Name) | ค่า (Value) |
   |---|---|
   | `BEAM_MERCHANT_ID` | Merchant ID ที่คัดลอกไว้จากขั้นตอน 3.2 |
   | `BEAM_API_KEY` | API Key ที่คัดลอกไว้จากขั้นตอน 3.2 |
   | `BEAM_API_BASE_URL` | `https://playground.api.beamcheckout.com` |
   | `BEAM_WEBHOOK_HMAC_KEY` | Webhook HMAC Key จากขั้นตอน 3.3 |

4. กด Save/Add ทีละตัวจนครบ 4 ค่า

### 4.2 Deploy ฟังก์ชันที่ 1: create-beam-charge

1. หน้า Edge Functions กดปุ่ม **Deploy a new function** (หรือ Create function)
2. เลือกโหมดเขียนโค้ดเอง (ไม่ใช่ upload ไฟล์จากเครื่อง)
3. ช่องชื่อฟังก์ชัน พิมพ์: `create-beam-charge` **(ต้องตรงตัวอักษรทุกตัว ตัวเล็กหมด มีขีดกลาง)**
4. ลบโค้ดตัวอย่างที่ขึ้นมาในกล่องแก้ไขโค้ดออกให้หมด
5. เปิดไฟล์ `supabase/functions/create-beam-charge/index.ts` ด้วยโปรแกรมข้อความ
6. คัดลอกทั้งหมด (Ctrl+A แล้ว Ctrl+C) มาวางแทนที่ (Ctrl+V) ในกล่องโค้ดของ Dashboard
7. กด **Deploy** มุมขวาบน รอจนขึ้นสถานะ **Deployed** (สีเขียว)

### 4.3 Deploy ฟังก์ชันที่ 2: check-beam-payment-status

ทำเหมือนข้อ 4.2 ทุกขั้นตอน แต่เปลี่ยน:
- ชื่อฟังก์ชัน: `check-beam-payment-status`
- โค้ดจากไฟล์: `supabase/functions/check-beam-payment-status/index.ts`

### 4.4 Deploy ฟังก์ชันที่ 3: beam-webhook (มีขั้นตอนพิเศษเพิ่ม 1 ข้อ)

ทำเหมือนข้อ 4.2 แต่เปลี่ยน:
- ชื่อฟังก์ชัน: `beam-webhook`
- โค้ดจากไฟล์: `supabase/functions/beam-webhook/index.ts`
- **ก่อนกด Deploy**: มองหาตัวเลือก **"Verify JWT"** หรือ **"Enforce JWT verification"** (มักเป็นสวิตช์เปิด-ปิด)
  แล้ว **ปิดมันลง (Off)** — จำเป็นมากเพราะ Beam ไม่ได้ส่งกุญแจของ Supabase มาด้วยตอนยิง webhook

หลังจากนี้ควรเห็นฟังก์ชันครบ 3 ตัวในหน้า Edge Functions สถานะ Deployed ทั้งหมด

---

## ขั้นตอนที่ 5: ตั้งค่า Webhook ใน Beam ให้ชี้มาที่เว็บเรา

1. กลับไปที่ **Beam Lighthouse** → Developers → Webhook Settings
2. ถ้าสร้าง webhook ไว้แล้วตอนขั้นตอน 3.3 ให้กดแก้ไข (Edit) หรือสร้างใหม่อีกอันก็ได้
3. ช่อง URL ใส่ (แทน `xxxxxxxxxxxxxxxxxxxx` ด้วย Project Reference ของคุณจากขั้นตอน 1.3):
   ```
   https://xxxxxxxxxxxxxxxxxxxx.supabase.co/functions/v1/beam-webhook
   ```
4. เลือก event ที่จะรับ: `charge.succeeded` และ `charge.failed`
5. กด Save

---

## ขั้นตอนที่ 6: สมัครสมาชิกและตั้งตัวเองเป็นแอดมิน

### 6.1 เปิดเว็บทดสอบก่อน (ยังไม่ต้อง deploy ขึ้นจริง)

ดับเบิลคลิกไฟล์ `index.html` ที่แก้ค่าไว้แล้ว (ขั้นตอนที่ 2) ให้เปิดในเบราว์เซอร์
**สำคัญ:** ต้องดับเบิลคลิกเปิดจากเครื่อง ไม่ใช่กดดูผ่านหน้าแชท เพราะปุ่มฟอร์มบางอย่างต้องเปิดในเบราว์เซอร์จริงถึงจะทำงาน

### 6.2 สมัครสมาชิก

1. กดปุ่ม **"เข้าสู่ระบบ"** มุมขวาบน
2. กดแท็บ **"สมัครสมาชิก"**
3. กรอกอีเมลที่จะใช้เป็นแอดมิน + รหัสผ่าน (อย่างน้อย 6 ตัวอักษร) + ชื่อที่แสดง (ใส่หรือไม่ใส่ก็ได้)
4. กด **สมัครสมาชิก**

> ถ้า Supabase บังคับให้ยืนยันอีเมลก่อนถึงจะล็อกอินได้ ให้เช็คอีเมลกดลิงก์ยืนยัน แล้วกลับมาล็อกอินใหม่

### 6.3 ตั้งบัญชีนี้เป็นแอดมิน

1. กลับไปที่ Supabase Dashboard → **SQL Editor** → New query
2. วางคำสั่งนี้ (**แก้อีเมลตรงกลางเป็นอีเมลที่เพิ่งสมัครไป**):
   ```sql
   update public.profiles set role = 'admin'
   where id = (select id from auth.users where email = 'YOUR_ADMIN_EMAIL@example.com');
   ```
3. กด Run ควรขึ้น **Success**

### 6.4 ทดสอบเข้าหน้าแอดมิน

1. กลับไปที่หน้าเว็บ (รีเฟรชหน้าใหม่ก่อน)
2. เลื่อนลงล่างสุดของหน้าเว็บ กดลิงก์ **"เข้าสู่ระบบแอดมิน"** ที่ footer
3. ถ้าล็อกอินค้างอยู่แล้ว ควรเข้าหน้าแอดมินได้ทันที เห็น 3 แท็บ: สถิติการขาย / จัดการนิยาย / ชุดเหรียญ

✅ ถ้าเข้าได้ แปลว่าระบบสมาชิก + ฐานข้อมูลทำงานถูกต้องหมดแล้ว

---

## ขั้นตอนที่ 7: ทดสอบระบบจ่ายเงิน (โหมด Playground ไม่ตัดเงินจริง)

1. ที่หน้าเว็บ กดป้ายเหรียญ (มุมขวาบน) → **"+ เติม"**
2. เลือกแพ็กเกจเหรียญใดก็ได้
3. ควรขึ้น QR PromptPay ภายในไม่กี่วินาที (ถ้าค้างนานหรือ error ดูหัวข้อแก้ปัญหาด้านล่าง)
4. โหมด Playground ของ Beam ไม่ต้องสแกนจริง — ดูวิธี simulate การจ่ายสำเร็จได้ที่หน้า Test Data ของ Beam
   (หรือถ้าไม่มีวิธี simulate ในบัญชีคุณ ให้กดปุ่ม **"ฉันชำระเงินแล้ว / เช็คสถานะ"** ทดสอบว่าฟังก์ชัน
   `check-beam-payment-status` ทำงานได้ ไม่ error อย่างน้อยก็พอ)

---

## ขั้นตอนที่ 8: Deploy เว็บขึ้นออนไลน์จริง (GitHub + Cloudflare Pages)

### 8.1 สร้าง GitHub Repository

1. ไปที่ **https://github.com** สมัคร/ล็อกอิน
2. กด **+** มุมขวาบน → **New repository**
3. ตั้งชื่อ เช่น `greenread` เลือก Public หรือ Private ก็ได้
4. กด **Create repository** (ไม่ต้องติ๊ก README/gitignore ใดๆ)

### 8.2 อัปโหลดไฟล์ index.html

1. ในหน้า repo ที่เพิ่งสร้าง กดลิงก์ **"uploading an existing file"**
2. ลากไฟล์ `index.html` (ตัวที่แก้ค่า Supabase แล้ว) มาวางในหน้าเว็บ
3. เลื่อนลงล่าง กด **Commit changes**

**สำคัญมาก:** ไฟล์ต้องชื่อ `index.html` เป๊ะๆ ห้ามเปลี่ยนชื่อ เพราะ Cloudflare Pages จะหาไฟล์ชื่อนี้เป็นหน้าแรก
โดยอัตโนมัติ ถ้าใช้ชื่ออื่นจะเข้าเว็บแล้วเจอหน้าเปล่า

### 8.3 เชื่อม Cloudflare Pages

1. ไปที่ **https://dash.cloudflare.com** สมัคร/ล็อกอิน
2. เมนูซ้าย กด **Workers & Pages**
3. กด **Create** → แท็บ **Pages** → **Connect to Git**
4. อนุญาตให้ Cloudflare เข้าถึง GitHub (ครั้งแรกเท่านั้น) แล้วเลือก repo `greenread`
5. หน้า "Set up builds and deployments":
   - **Framework preset**: None
   - **Build command**: เว้นว่างไว้
   - **Build output directory**: `/`
6. กด **Save and Deploy**
7. รอ 1-2 นาที จะได้ลิงก์ `https://greenread-xxx.pages.dev` — เปิดลิงก์นี้เว็บควรใช้งานได้จริงแล้ว

---

## ขั้นตอนที่ 9: เปลี่ยนเป็นเงินจริง (ทำตอนพร้อมเปิดขายจริง)

ตอนนี้ทั้งหมดยังอยู่ในโหมด Playground (ไม่ตัดเงินจริง) เมื่อพร้อมใช้จริง:

1. กลับไป Beam Lighthouse → สลับโหมดเป็น **Production** → เอา Merchant ID / API Key / Webhook HMAC Key
   ชุดใหม่ (คนละชุดกับ Playground)
2. ไปที่ Supabase Edge Functions → Secrets → แก้ไข 4 ค่าเดิมให้เป็นชุด Production:
   - `BEAM_MERCHANT_ID` → ของ Production
   - `BEAM_API_KEY` → ของ Production
   - `BEAM_API_BASE_URL` → เปลี่ยนเป็น `https://api.beamcheckout.com`
   - `BEAM_WEBHOOK_HMAC_KEY` → ของ Production
3. ตั้ง Webhook ใหม่ในโหมด Production ของ Beam (URL เดิม แค่คนละโหมด)
4. ทดสอบจ่ายเงินจริงยอดน้อยๆ ดูก่อนเปิดขายจริง

---

## แก้ปัญหาที่พบบ่อย

### "Failed to run sql query: ERROR: syntax error at or near //"
วางโค้ดผิดที่ — โค้ด `.ts` (Edge Function) ไปวางใน SQL Editor เอาออกให้หมด แล้ววาง `setup.sql` แทน
ส่วนโค้ด `.ts` ต้องวางที่หน้า **Edge Functions** เท่านั้น (ดูขั้นตอนที่ 4)

### "column role does not exist" ตอนรัน setup.sql
โปรเจกต์มีตาราง `profiles` อยู่ก่อนแล้วจากเทมเพลตอื่น — ไฟล์ `setup.sql` เวอร์ชันล่าสุดแก้ปัญหานี้ให้แล้ว
เช็คว่าใช้ไฟล์ล่าสุดที่ให้ไป ไม่ใช่ไฟล์เก่า

### กดปุ่มในเว็บแล้วไม่มีอะไรเกิดขึ้นเลย (ป็อปอัพค้าง)
เปิดเว็บผ่านการกดดูในหน้าแชท ให้ดาวน์โหลดไฟล์มาเก็บที่เครื่องก่อน แล้วดับเบิลคลิกเปิดด้วยเบราว์เซอร์โดยตรง

### หน้าเว็บว่างเปล่า ไม่มีข้อมูลนิยายขึ้น
เช็ค 2 จุด: (1) แก้ `SUPABASE_URL`/`SUPABASE_ANON_KEY` ในไฟล์ index.html แล้วหรือยัง (2) กด F12 เปิด Console
ดู error สีแดง แล้วส่งข้อความ error มาถามได้

### เข้าหน้าแอดมินไม่ได้
ต้องสมัครสมาชิกก่อน แล้วรันคำสั่ง SQL ตั้ง role='admin' ตามขั้นตอน 6.3 ให้ตรงกับอีเมลที่ใช้สมัครเป๊ะๆ

### QR เติมเหรียญไม่ขึ้น หรือขึ้น error
เช็คว่า deploy ครบทั้ง 3 ฟังก์ชันแล้ว และตั้ง secrets ครบ 4 ค่าถูกต้อง (โดยเฉพาะ `BEAM_MERCHANT_ID`
กับ `BEAM_API_KEY` พิมพ์ผิดหรือเว้นวรรคเกินมักเป็นสาเหตุที่พบบ่อยที่สุด)

### เปิดเว็บบน Cloudflare Pages แล้วเจอหน้าเปล่า/หน้า 404
ไฟล์ที่อัปโหลดไป GitHub ต้องชื่อ `index.html` เป๊ะๆ ตรวจดูใน repo ว่าชื่อไฟล์ถูกต้อง

---

**ทำไม่ได้ตรงไหน ส่งข้อความ error หรือสกรีนช็อตมาได้เลย จะช่วยไล่ดูให้ตรงจุด**
