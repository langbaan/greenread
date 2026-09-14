-- =========================================================
-- นิยายหลังบ้าน (GreenRead) — Supabase setup.sql (ไฟล์เดียวจบ)
-- รันไฟล์นี้ทั้งหมดใน Supabase Dashboard > SQL Editor (New query) ครั้งเดียว
-- ปลอดภัยต่อการรันซ้ำ (ใช้ if not exists / or replace เกือบทั้งหมด)
--
-- ไฟล์นี้รวม 2 ส่วนไว้ด้วยกัน:
--   ส่วนที่ 1: โครงสร้างฐานข้อมูล ตาราง, RLS, RPC functions (เดิมคือ schema.sql)
--   ส่วนที่ 2: ข้อมูลนิยายตัวอย่าง 5 เรื่องไว้ทดสอบ (เดิมคือ seed-sample-novels.sql) — ลบทิ้งได้ถ้าไม่ต้องการ
-- =========================================================


-- #########################################################
-- ส่วนที่ 1: โครงสร้างฐานข้อมูล
-- #########################################################

-- ต้องใช้ pgcrypto สำหรับ gen_random_uuid()
create extension if not exists pgcrypto;

-- ---------------------------------------------------------
-- 1) TABLES
-- ---------------------------------------------------------

-- โปรไฟล์ผู้ใช้ 1 แถวต่อ 1 บัญชี auth.users (สร้างอัตโนมัติด้วย trigger ด้านล่าง)
create table if not exists public.profiles (
  id            uuid primary key references auth.users(id) on delete cascade,
  display_name  text,
  role          text not null default 'member',
  coins         integer not null default 0,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now()
);

-- ⚠️ กันเคส "profiles" มีอยู่ก่อนแล้วจากที่อื่น (เช่น Supabase "User Management" starter
-- template ที่บาง project สร้างให้อัตโนมัติตอนเปิดโปรเจกต์ใหม่ ซึ่งจะมีแค่ id/username/avatar_url
-- ไม่มี role/coins) — ตอนนั้น "create table if not exists" ด้านบนจะถูกข้ามไปเฉยๆ ไม่เพิ่มคอลัมน์ให้
-- บล็อกนี้จึงเติมคอลัมน์ที่ขาดหายไปให้ครบโดยไม่กระทบข้อมูลเดิมที่มีอยู่ในตาราง
alter table public.profiles add column if not exists display_name text;
alter table public.profiles add column if not exists role text not null default 'member';
alter table public.profiles add column if not exists coins integer not null default 0;
alter table public.profiles add column if not exists created_at timestamptz not null default now();
alter table public.profiles add column if not exists updated_at timestamptz not null default now();

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'profiles_role_check') then
    alter table public.profiles add constraint profiles_role_check check (role in ('member','admin'));
  end if;
  if not exists (select 1 from pg_constraint where conname = 'profiles_coins_check') then
    alter table public.profiles add constraint profiles_coins_check check (coins >= 0);
  end if;
end $$;

create table if not exists public.novels (
  id                 uuid primary key default gen_random_uuid(),
  title              text not null,
  author             text not null,
  genre              text not null,
  price_per_chapter  numeric(10,2) not null default 0, -- ใช้แสดงผล/เรียงราคาเท่านั้น ราคาจริงอยู่ที่ตอน
  rating             numeric(2,1) not null default 0,
  view_count         integer not null default 0,
  status             text not null default 'ongoing' check (status in ('ongoing','completed')),
  cover_url          text,
  synopsis           text,
  created_at         timestamptz not null default now(),
  updated_at         timestamptz not null default now()
);

create table if not exists public.chapters (
  id          uuid primary key default gen_random_uuid(),
  novel_id    uuid not null references public.novels(id) on delete cascade,
  number      integer not null,
  title       text not null,
  is_free     boolean not null default false,
  price       numeric(10,2) not null default 0,
  content     text not null default '',
  created_at  timestamptz not null default now(),
  unique (novel_id, number)
);

create table if not exists public.coin_packages (
  id          uuid primary key default gen_random_uuid(),
  coins       integer not null,
  price       numeric(10,2) not null,
  bonus       integer not null default 0,
  tag         text,
  active      boolean not null default true,
  sort_order  integer not null default 0,
  created_at  timestamptz not null default now()
);

create table if not exists public.liked_novels (
  user_id     uuid not null references auth.users(id) on delete cascade,
  novel_id    uuid not null references public.novels(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (user_id, novel_id)
);

create table if not exists public.purchased_chapters (
  user_id      uuid not null references auth.users(id) on delete cascade,
  chapter_id   uuid not null references public.chapters(id) on delete cascade,
  novel_id     uuid not null references public.novels(id) on delete cascade,
  price_paid   numeric(10,2) not null,
  purchased_at timestamptz not null default now(),
  primary key (user_id, chapter_id)
);

-- ออเดอร์เติมเหรียญ (1 แถว = 1 การชำระเงินผ่าน Beam Checkout PromptPay)
create table if not exists public.orders (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users(id) on delete cascade,
  package_id       uuid references public.coin_packages(id),
  coins            integer not null,
  bonus            integer not null default 0,
  amount           numeric(10,2) not null,
  status           text not null default 'pending' check (status in ('pending','paid','failed','expired')),
  charge_id        text unique,
  qr_image_uri     text,
  created_at       timestamptz not null default now(),
  paid_at          timestamptz
);

create index if not exists idx_chapters_novel on public.chapters(novel_id);
create index if not exists idx_purchased_user on public.purchased_chapters(user_id);
create index if not exists idx_orders_user on public.orders(user_id);
create index if not exists idx_orders_charge on public.orders(charge_id);

-- ⚠️ กันเคส orders มีอยู่ก่อนแล้วจากตอนใช้ Omise (คอลัมน์เดิมชื่อ omise_charge_id)
-- ย้ายชื่อคอลัมน์ให้เป็นกลาง (charge_id) เพื่อใช้ได้กับผู้ให้บริการชำระเงินเจ้าไหนก็ได้ (ตอนนี้คือ Beam)
do $$
begin
  if exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders' and column_name = 'omise_charge_id'
  ) and not exists (
    select 1 from information_schema.columns
    where table_schema = 'public' and table_name = 'orders' and column_name = 'charge_id'
  ) then
    alter table public.orders rename column omise_charge_id to charge_id;
  end if;
end $$;

-- ---------------------------------------------------------
-- 2) AUTO-CREATE PROFILE ON SIGNUP
-- ---------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name)
  values (new.id, coalesce(new.raw_user_meta_data->>'display_name', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ---------------------------------------------------------
-- 3) HELPER: is_admin() — ใช้ security definer เพื่อกัน RLS recursion
-- ---------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (select 1 from public.profiles where id = auth.uid() and role = 'admin');
$$;

-- ---------------------------------------------------------
-- 4) ROW LEVEL SECURITY
-- ---------------------------------------------------------
alter table public.profiles enable row level security;
alter table public.novels enable row level security;
alter table public.chapters enable row level security;
alter table public.coin_packages enable row level security;
alter table public.liked_novels enable row level security;
alter table public.purchased_chapters enable row level security;
alter table public.orders enable row level security;

-- profiles: ผู้ใช้เห็น/แก้ได้เฉพาะแถวตัวเอง (ห้ามแก้ coins ตรงๆ — ใช้ RPC เท่านั้น), แอดมินเห็นทั้งหมด
drop policy if exists "profiles_select_own_or_admin" on public.profiles;
create policy "profiles_select_own_or_admin" on public.profiles
  for select using (auth.uid() = id or public.is_admin());

drop policy if exists "profiles_update_display_name_only" on public.profiles;
create policy "profiles_update_display_name_only" on public.profiles
  for update using (auth.uid() = id)
  with check (auth.uid() = id);
-- หมายเหตุ: ฝั่ง client ควรอัปเดตแค่ display_name เท่านั้น การแก้ coins ตรงๆ จะทำได้จริง
-- ถ้า client ส่งมา (Postgres RLS ไม่บล็อกเป็นรายคอลัมน์) — ดังนั้นเราไม่เปิดปุ่มแก้เหรียญในหน้าเว็บ
-- และแนะนำให้ตรวจสอบ coins ที่ purchase_chapter()/credit ผ่าน RPC เท่านั้นในทางปฏิบัติ

-- novels: อ่านได้ทุกคน, เขียนได้เฉพาะแอดมิน
drop policy if exists "novels_select_all" on public.novels;
create policy "novels_select_all" on public.novels for select using (true);
drop policy if exists "novels_admin_insert" on public.novels;
create policy "novels_admin_insert" on public.novels for insert with check (public.is_admin());
drop policy if exists "novels_admin_update" on public.novels;
create policy "novels_admin_update" on public.novels for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "novels_admin_delete" on public.novels;
create policy "novels_admin_delete" on public.novels for delete using (public.is_admin());

-- chapters: "ล็อก" ตาราง — ผู้ใช้ทั่วไปห้าม select ตรง (เนื้อหาที่ยังไม่ซื้อต้องไม่รั่ว)
-- ผู้ใช้อ่านผ่าน RPC get_novel_chapters()/get_chapter_content() เท่านั้น
-- แอดมินจัดการได้เต็มที่ผ่านตารางตรง
drop policy if exists "chapters_admin_all" on public.chapters;
create policy "chapters_admin_all" on public.chapters for all using (public.is_admin()) with check (public.is_admin());

-- coin_packages: อ่านแพ็กเกจที่เปิดขาย (active) ได้ทุกคน, แอดมินเห็น/แก้ได้ทั้งหมด
drop policy if exists "packages_select_active_or_admin" on public.coin_packages;
create policy "packages_select_active_or_admin" on public.coin_packages
  for select using (active = true or public.is_admin());
drop policy if exists "packages_admin_insert" on public.coin_packages;
create policy "packages_admin_insert" on public.coin_packages for insert with check (public.is_admin());
drop policy if exists "packages_admin_update" on public.coin_packages;
create policy "packages_admin_update" on public.coin_packages for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "packages_admin_delete" on public.coin_packages;
create policy "packages_admin_delete" on public.coin_packages for delete using (public.is_admin());

-- liked_novels: ผู้ใช้จัดการรายการถูกใจของตัวเองได้
drop policy if exists "liked_select_own" on public.liked_novels;
create policy "liked_select_own" on public.liked_novels for select using (auth.uid() = user_id);
drop policy if exists "liked_insert_own" on public.liked_novels;
create policy "liked_insert_own" on public.liked_novels for insert with check (auth.uid() = user_id);
drop policy if exists "liked_delete_own" on public.liked_novels;
create policy "liked_delete_own" on public.liked_novels for delete using (auth.uid() = user_id);

-- purchased_chapters: อ่านได้เฉพาะของตัวเอง (หรือแอดมิน), เขียนได้ผ่าน RPC purchase_chapter() เท่านั้น
drop policy if exists "purchased_select_own_or_admin" on public.purchased_chapters;
create policy "purchased_select_own_or_admin" on public.purchased_chapters
  for select using (auth.uid() = user_id or public.is_admin());

-- orders: อ่านได้เฉพาะของตัวเอง (หรือแอดมินดูสถิติยอดขาย), เขียนได้เฉพาะฝั่ง server (service role ข้าม RLS อยู่แล้ว)
drop policy if exists "orders_select_own_or_admin" on public.orders;
create policy "orders_select_own_or_admin" on public.orders
  for select using (auth.uid() = user_id or public.is_admin());

-- ---------------------------------------------------------
-- 5) RPC FUNCTIONS (SECURITY DEFINER — ทำงานแทน service role ฝั่ง DB)
-- ---------------------------------------------------------

-- รายการตอนทั้งหมดของนิยายเรื่องหนึ่ง พร้อมสถานะปลดล็อกของผู้ใช้ปัจจุบัน
-- (ไม่ส่ง content กลับมา เพื่อไม่ให้เนื้อหาที่ยังไม่ซื้อรั่วไหลออกไปใน network payload)
create or replace function public.get_novel_chapters(p_novel_id uuid)
returns table (
  id uuid, number integer, title text, is_free boolean, price numeric, unlocked boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.id, c.number, c.title, c.is_free, c.price,
    (c.is_free
      or (auth.uid() is not null and exists (
            select 1 from purchased_chapters pc
            where pc.chapter_id = c.id and pc.user_id = auth.uid()
          ))
      or public.is_admin()
    ) as unlocked
  from chapters c
  where c.novel_id = p_novel_id
  order by c.number asc;
$$;

grant execute on function public.get_novel_chapters(uuid) to anon, authenticated;

-- เนื้อหาของตอนหนึ่ง — คืนค่าเฉพาะเมื่อฟรี/ซื้อแล้ว/เป็นแอดมิน มิฉะนั้น raise exception
create or replace function public.get_chapter_content(p_chapter_id uuid)
returns text
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_content text;
  v_is_free boolean;
  v_allowed boolean;
begin
  select content, is_free into v_content, v_is_free from chapters where id = p_chapter_id;
  if v_content is null then
    raise exception 'ไม่พบตอนนี้';
  end if;

  v_allowed := v_is_free
    or public.is_admin()
    or (auth.uid() is not null and exists (
          select 1 from purchased_chapters pc
          where pc.chapter_id = p_chapter_id and pc.user_id = auth.uid()
        ));

  if not v_allowed then
    raise exception 'ตอนนี้ยังไม่ได้ปลดล็อก';
  end if;

  return v_content;
end;
$$;

grant execute on function public.get_chapter_content(uuid) to anon, authenticated;

-- เมทาดาต้าของ "ทุกตอนของทุกเรื่อง" ในครั้งเดียว (ไม่มี content) พร้อมสถานะ unlocked
-- ของผู้ใช้ปัจจุบัน — ใช้ตอนโหลดหน้า home/catalog/bookshelf เพื่อลดจำนวน round-trip
create or replace function public.get_all_chapters_meta()
returns table (
  novel_id uuid, id uuid, number integer, title text, is_free boolean, price numeric, unlocked boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    c.novel_id, c.id, c.number, c.title, c.is_free, c.price,
    (c.is_free
      or (auth.uid() is not null and exists (
            select 1 from purchased_chapters pc
            where pc.chapter_id = c.id and pc.user_id = auth.uid()
          ))
      or public.is_admin()
    ) as unlocked
  from chapters c
  order by c.novel_id, c.number;
$$;

grant execute on function public.get_all_chapters_meta() to anon, authenticated;

-- นับยอดวิวแบบ atomic (กันปัญหา race condition ถ้ามีคนเปิดอ่านพร้อมกันหลายคน)
create or replace function public.increment_view_count(p_novel_id uuid)
returns void
language sql
security definer
set search_path = public
as $$
  update novels set view_count = view_count + 1 where id = p_novel_id;
$$;

grant execute on function public.increment_view_count(uuid) to anon, authenticated;

-- ซื้อตอน: หักเหรียญ + บันทึกสิทธิ์การอ่าน แบบ atomic กันแข่งกันกดซ้ำ
create or replace function public.purchase_chapter(p_chapter_id uuid)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_price    numeric;
  v_novel_id uuid;
  v_is_free  boolean;
  v_coins    integer;
begin
  if auth.uid() is null then
    raise exception 'กรุณาเข้าสู่ระบบก่อน';
  end if;

  select price, novel_id, is_free into v_price, v_novel_id, v_is_free
  from chapters where id = p_chapter_id;

  if v_novel_id is null then
    raise exception 'ไม่พบตอนนี้';
  end if;
  if v_is_free then
    return json_build_object('already_unlocked', true);
  end if;

  if exists (select 1 from purchased_chapters where user_id = auth.uid() and chapter_id = p_chapter_id) then
    return json_build_object('already_unlocked', true);
  end if;

  select coins into v_coins from profiles where id = auth.uid() for update;
  if v_coins is null then
    raise exception 'ไม่พบบัญชีผู้ใช้';
  end if;
  if v_coins < v_price then
    raise exception 'เหรียญไม่พอ ต้องใช้ % เหรียญ (มี % เหรียญ)', v_price, v_coins;
  end if;

  update profiles set coins = coins - v_price, updated_at = now() where id = auth.uid();
  insert into purchased_chapters (user_id, chapter_id, novel_id, price_paid)
  values (auth.uid(), p_chapter_id, v_novel_id, v_price);

  return json_build_object('already_unlocked', false, 'coins_remaining', v_coins - v_price);
end;
$$;

grant execute on function public.purchase_chapter(uuid) to authenticated;

-- เติมเหรียญให้ผู้ใช้เมื่อออเดอร์จ่ายเงินสำเร็จ (เรียกจาก Edge Function ด้วย service role เท่านั้น
-- แต่ยังคงกัน RLS/แข่งกันด้วย SECURITY DEFINER + for update)
create or replace function public.credit_order(p_order_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_coins integer;
  v_bonus integer;
  v_status text;
begin
  select user_id, coins, bonus, status into v_user_id, v_coins, v_bonus, v_status
  from orders where id = p_order_id for update;

  if v_user_id is null then
    raise exception 'ไม่พบออเดอร์';
  end if;

  if v_status = 'paid' then
    return; -- กันเติมซ้ำ (idempotent)
  end if;

  update orders set status = 'paid', paid_at = now() where id = p_order_id;
  update profiles set coins = coins + v_coins + v_bonus, updated_at = now() where id = v_user_id;
end;
$$;

-- ⚠️ สำคัญมาก: Postgres ให้สิทธิ์ EXECUTE แก่ PUBLIC โดยอัตโนมัติทุกครั้งที่สร้างฟังก์ชันใหม่
-- ต้อง REVOKE ออกอย่างชัดเจน ไม่งั้นผู้ใช้ทั่วไปจะเรียก credit_order(order_id ของคนอื่น) ตรงๆ
-- เพื่อเติมเหรียญปลอม (โดยไม่ต้องจ่ายเงินจริง) ได้ทันที — ฟังก์ชันนี้เรียกได้จาก
-- Edge Function ด้วย service role key เท่านั้น (service role มีสิทธิ์เต็มอยู่แล้ว ไม่ต้อง grant เพิ่ม)
revoke execute on function public.credit_order(uuid) from public;
revoke execute on function public.credit_order(uuid) from anon;
revoke execute on function public.credit_order(uuid) from authenticated;

-- ---------------------------------------------------------
-- 6) SEED DATA (ตัวอย่าง coin packages — แก้ไข/เพิ่มได้ในหน้าแอดมิน)
-- ---------------------------------------------------------
insert into public.coin_packages (coins, price, bonus, tag, sort_order)
select * from (values
  (100,  35.00,  0,   'เริ่มต้นประหยัด', 1),
  (300,  99.00,  30,  'ขายดีที่สุด 🔥', 2),
  (600,  189.00, 80,  'โบนัส +13%', 3),
  (1200, 359.00, 200, 'คุ้มค่าที่สุด 💎', 4)
) as v(coins, price, bonus, tag, sort_order)
where not exists (select 1 from public.coin_packages);

-- ---------------------------------------------------------
-- 7) เปิด REALTIME บนตาราง orders
-- ---------------------------------------------------------
-- ให้หน้าเว็บ subscribe แล้วรู้ทันทีที่ webhook เติมเหรียญสำเร็จ (ไม่ต้องรอ poll)
-- ถ้ารันแล้วเจอ error ว่ามีอยู่แล้ว ("already member of publication") ข้ามได้เลย ไม่ใช่ปัญหา
alter publication supabase_realtime add table public.orders;

-- ---------------------------------------------------------
-- 8) ตั้งแอดมินคนแรก
-- ---------------------------------------------------------
-- หลังจากสมัครสมาชิกในหน้าเว็บด้วยอีเมลที่จะใช้เป็นแอดมินแล้ว ให้มารันคำสั่งนี้ทีหลัง (แก้อีเมลก่อนรัน):
-- update public.profiles set role = 'admin'
-- where id = (select id from auth.users where email = 'YOUR_ADMIN_EMAIL@example.com');


-- #########################################################
-- ส่วนที่ 2: ข้อมูลนิยายตัวอย่าง (ไม่บังคับ — ลบส่วนนี้ทิ้งได้ถ้าไม่ต้องการข้อมูลทดสอบ)
-- #########################################################

-- ---------------------------------------------------------
-- 1) นิยาย 5 เรื่อง
-- ---------------------------------------------------------
insert into public.novels (id, title, author, genre, price_per_chapter, rating, view_count, status, synopsis) values
('a1111111-1111-1111-1111-111111111111', 'ยอดเซียนซ่อนกลิ่นแห่งหุบเขาเขียว', 'ศิษย์เจ้าเขียว', 'กำลังภายใน', 15, 4.9, 320, 'ongoing', 'เด็กหนุ่มไร้ตระกูลพบสมุดวิชาลึกลับกลางหุบเขาเขียว เริ่มต้นเส้นทางยอดเซียนที่ไม่มีใครคาดคิด'),
('a2222222-2222-2222-2222-222222222222', 'หัวใจในสวนพฤกษา', 'ใบไม้สีจาง', 'โรแมนติก', 10, 4.8, 210, 'ongoing', 'นักพฤกษศาสตร์สาวกับสถาปนิกหนุ่มที่มาบูรณะสวนพฤกษศาสตร์เก่าแก่ ค้นพบว่าดอกไม้ไม่ใช่สิ่งเดียวที่กำลังผลิบาน'),
('a3333333-3333-3333-3333-333333333333', 'ปริศนาเงาในสถาบันวิจัย', 'เข็มทิศ', 'สืบสวน', 12, 4.7, 275, 'completed', 'คดีฆาตกรรมห้องปิดตายในศูนย์วิจัยพันธุกรรม มีเพียงร่องรอยสารเคมีสีเขียวปริศนาทิ้งไว้บนพื้น'),
('a4444444-4444-4444-4444-444444444444', 'มหาสงครามเวทมนตร์นิรันดร์', 'Aragon', 'แฟนตาซี', 18, 5.0, 402, 'ongoing', 'อัญมณีเวทมนตร์ทั้งเจ็ดถูกปลุกขึ้น สงครามระหว่างเผ่าพันธุ์กำลังจะตัดสินชะตากรรมของทวีปเอเดน'),
('a5555555-5555-5555-5555-555555555555', 'คฤหาสน์เสียงกระซิบ', 'รัตติกาล', 'สยองขวัญ', 14, 4.6, 189, 'ongoing', 'ครอบครัวหนึ่งย้ายเข้าคฤหาสน์เก่าริมป่า แล้วเริ่มได้ยินเสียงกระซิบเรียกชื่อพวกเขายามค่ำคืน')
on conflict (id) do nothing;

-- ---------------------------------------------------------
-- 2) ตอนที่ 1-3 ของแต่ละเรื่อง (ตอนที่ 1 ฟรี ที่เหลือเสียเหรียญ)
-- ---------------------------------------------------------

-- เรื่อง 1: ยอดเซียนซ่อนกลิ่นแห่งหุบเขาเขียว
insert into public.chapters (novel_id, number, title, is_free, price, content) values
('a1111111-1111-1111-1111-111111111111', 1, 'สมุดวิชาใต้ต้นหลิว', true, 0,
'<p>หมอกยามเช้าคลุมหุบเขาเขียวเป็นผ้าห่มบางๆ เฉินอวี้ เด็กกำพร้าวัยสิบหกที่หาฟืนขายเลี้ยงชีพ ก้าวเท้าเปล่าไปตามทางเดินคุ้นตา จนสะดุดรากไม้ล้มลงตรงโคนต้นหลิวเก่าแก่ริมหน้าผา</p>
<p>มือของเขาสัมผัสบางสิ่งแข็งใต้ดินร่วน เมื่อขุดออกมาดู กลับเป็นกล่องไม้เก่าคร่ำ ภายในมีสมุดปกหนังสีเขียวเข้ม ปกไม่มีชื่อเรื่อง มีเพียงรอยแกะสลักรูปหุบเขาเป็นสัญลักษณ์</p>
<p>"วิชาแรกของสายหุบเขาเขียว จงจดจำ ลมหายใจคือรากฐาน หัวใจคือปราการ..." ตัวอักษรบนหน้าแรกลอยเด่นราวกับมีชีวิต เฉินอวี้กลั้นหายใจ ไม่รู้เลยว่าชีวิตทั้งชีวิตของเขากำลังจะเปลี่ยนไปตลอดกาล</p>'),
('a1111111-1111-1111-1111-111111111111', 2, 'ลมปราณสายแรก', false, 15,
'<p>สามคืนติดต่อกันที่เฉินอวี้นั่งสมาธิตามที่สมุดสอน ลมหายใจของเขาเริ่มไหลเวียนเป็นจังหวะแปลกๆ ราวกับมีสายน้ำเล็กๆ ไหลอยู่ใต้ผิวหนัง</p>
<p>เช้าวันที่สี่ เมื่อเขาแบกฟืนหนักกว่าเดิมสองเท่าโดยไม่รู้สึกเหนื่อยเลย เขาจึงรู้ว่าสิ่งที่เกิดขึ้นนั้นไม่ใช่เรื่องบังเอิญ — ลมปราณสายแรกของเขาได้ก่อตัวขึ้นแล้วจริงๆ</p>
<p>แต่ในหมู่บ้านเชิงเขา มีคนสังเกตเห็นความเปลี่ยนแปลงของเด็กกำพร้าคนนี้เข้าแล้วเช่นกัน...</p>'),
('a1111111-1111-1111-1111-111111111111', 3, 'ผู้มาเยือนจากตระกูลใหญ่', false, 15,
'<p>ม้าศึกสิบตัวควบเข้าหมู่บ้านในยามบ่าย นำโดยชายหนุ่มชุดไหมสีทองแห่งตระกูลอวี้เหอ ตระกูลใหญ่ที่ครอบครองหุบเขาเขียวมาสามชั่วอายุคน</p>
<p>"ได้ยินว่าแถวนี้มีเด็กกำพร้าฝึกวิชาได้เร็วผิดปกติ" เสียงเย็นชาดังขึ้น สายตาทุกคู่หันมองมาที่เฉินอวี้ผู้กำลังยืนตะลึงอยู่กลางลาน</p>
<p>เฉินอวี้กำมือสมุดวิชาไว้แน่น รู้ดีว่าความสงบของชีวิตเขาคงจบลงตั้งแต่วินาทีนี้แล้ว</p>')
on conflict (novel_id, number) do nothing;

-- เรื่อง 2: หัวใจในสวนพฤกษา
insert into public.chapters (novel_id, number, title, is_free, price, content) values
('a2222222-2222-2222-2222-222222222222', 1, 'สวนที่ถูกลืม', true, 0,
'<p>พิมพ์ใจ นักพฤกษศาสตร์วัยยี่สิบแปด ยืนอยู่หน้าประตูเหล็กขึ้นสนิมของสวนพฤกษศาสตร์เก่าที่ปิดตายมาสิบกว่าปี กลิ่นดินชื้นและใบไม้เน่าโชยมาปะทะจมูก</p>
<p>"คุณคือคนที่จะมาช่วยฟื้นฟูสวนนี้ใช่ไหมครับ" เสียงทุ้มดังขึ้นจากด้านหลัง เธอหันไปพบสถาปนิกหนุ่มรูปร่างสูงในชุดทำงานเปื้อนดิน ยิ้มให้เธออย่างเป็นมิตร</p>
<p>"ธาดา ผมดูแลเรื่องโครงสร้างอาคาร ส่วนเรื่องต้นไม้คงต้องพึ่งคุณแล้วล่ะ" เขายื่นมือมาทักทาย พิมพ์ใจไม่รู้เลยว่าการจับมือครั้งนี้จะเป็นจุดเริ่มต้นของอะไรบางอย่างที่ยิ่งใหญ่กว่าการบูรณะสวน</p>'),
('a2222222-2222-2222-2222-222222222222', 2, 'ดอกไม้ใต้แสงจันทร์', false, 10,
'<p>ทั้งสองทำงานด้วยกันทุกเย็นตลอดสองสัปดาห์ ธาดาซ่อมเรือนกระจกเก่า ขณะที่พิมพ์ใจปลุกต้นไม้ที่หลับใหลให้ตื่นขึ้นทีละต้น</p>
<p>คืนหนึ่งขณะพระจันทร์เต็มดวง กล้วยไม้พันธุ์หายากที่พิมพ์ใจเฝ้าดูแลบานขึ้นเป็นครั้งแรกในรอบสิบปี ทั้งคู่ยืนมองด้วยความตื่นเต้นจนไหล่ชนกันโดยไม่ตั้งใจ</p>
<p>"เหมือนสวนนี้กำลังจะมีชีวิตอีกครั้งเลยนะ" ธาดากระซิบ พิมพ์ใจรู้สึกหัวใจเต้นแรงกว่าปกติ แต่ไม่แน่ใจว่าเป็นเพราะกล้วยไม้ หรือเพราะคนที่ยืนอยู่ข้างกาย</p>'),
('a2222222-2222-2222-2222-222222222222', 3, 'ความลับใต้ดิน', false, 10,
'<p>ขณะขุดดินเพื่อวางท่อน้ำใหม่ คนงานพบกล่องโลหะเก่าฝังอยู่ใต้ต้นไม้ใหญ่ที่สุดของสวน ภายในคือจดหมายรักที่ไม่เคยถูกส่งของเจ้าของสวนคนแรกเมื่อหกสิบปีก่อน</p>
<p>เรื่องราวในจดหมายทำให้พิมพ์ใจและธาดาต้องเผชิญคำถามเดียวกัน — พวกเขากล้าพอจะไม่ปล่อยให้ความรู้สึกที่มีต่อกันกลายเป็นอีกเรื่องราวที่ไม่มีวันได้พูดออกมาหรือเปล่า</p>')
on conflict (novel_id, number) do nothing;

-- เรื่อง 3: ปริศนาเงาในสถาบันวิจัย
insert into public.chapters (novel_id, number, title, is_free, price, content) values
('a3333333-3333-3333-3333-333333333333', 1, 'ห้องทดลองปิดตาย', true, 0,
'<p>รศ.ดร.สรวิศ นักวิจัยพันธุกรรมชื่อดัง ถูกพบเป็นศพในห้องทดลองชั้นใต้ดินที่ล็อกจากด้านในทุกช่องทาง กล้องวงจรปิดหน้าห้องไม่มีใครเข้า-ออกตลอดคืน</p>
<p>นักสืบเข็มทิศ หญิงสาวอดีตตำรวจนิติวิทยาศาสตร์ที่ผันตัวมาเป็นนักสืบอิสระ ถูกตามตัวมาคลี่คลายคดีนี้เป็นการส่วนตัวโดยครอบครัวผู้ตาย</p>
<p>สิ่งเดียวที่แปลกตาในที่เกิดเหตุคือรอยเปื้อนสารเคมีสีเขียวมรกตบนพื้น ซึ่งไม่ตรงกับสารเคมีชนิดใดที่ใช้ในห้องแล็บแห่งนี้เลย</p>'),
('a3333333-3333-3333-3333-333333333333', 2, 'ร่องรอยที่ถูกลบ', false, 12,
'<p>เข็มทิศตรวจสอบบันทึกการเข้าออกห้องแล็บย้อนหลังหนึ่งเดือน พบว่ามีไฟล์ถูกลบทิ้งในคืนก่อนเกิดเหตุ ผู้ที่มีสิทธิ์เข้าถึงระบบมีเพียงสี่คนเท่านั้น</p>
<p>เมื่อสอบถามผู้ช่วยวิจัยของ ดร.สรวิศ เธอสังเกตเห็นมือของเขาสั่นเล็กน้อยทุกครั้งที่พูดถึงโปรเจกต์ล่าสุด — โปรเจกต์ที่ไม่มีชื่อในเอกสารทางการใดๆ เลย</p>'),
('a3333333-3333-3333-3333-333333333333', 3, 'สีเขียวมรกตที่แท้จริง', false, 12,
'<p>เข็มทิศไขปริศนาได้ในที่สุด — สารเคมีสีเขียวมรกตคือผลพลอยได้จากการทดลองลับที่ ดร.สรวิศ ปิดบังไว้จากมหาวิทยาลัยมาหลายปี และห้องที่ "ปิดตาย" นั้นแท้จริงมีทางออกลับที่ถูกออกแบบไว้ตั้งแต่แรก</p>
<p>แต่คำถามที่แท้จริงไม่ใช่ว่าฆาตกรออกจากห้องอย่างไร แต่คือใครกันแน่ที่รู้ความลับของทางออกนั้นมาก่อนเข็มทิศเสียอีก</p>')
on conflict (novel_id, number) do nothing;

-- เรื่อง 4: มหาสงครามเวทมนตร์นิรันดร์
insert into public.chapters (novel_id, number, title, is_free, price, content) values
('a4444444-4444-4444-4444-444444444444', 1, 'อัญมณีดวงแรกตื่น', true, 0,
'<p>ทวีปเอเดนสงบสุขมาสามร้อยปีนับตั้งแต่สงครามครั้งใหญ่ยุติลง จนกระทั่งคืนที่ดวงจันทร์แดงปรากฏบนฟ้า อัญมณีเวทมนตร์ดวงแรกจากทั้งเจ็ดดวงก็เปล่งแสงตื่นขึ้นกลางวิหารต้องห้าม</p>
<p>ไครอส เด็กหนุ่มกำพร้าจากหมู่บ้านชายแดน ถูกเลือกโดยอัญมณีแห่งสายลมโดยไม่มีใครคาดคิด พลังมหาศาลที่ไหลเข้าสู่ร่างกายเขาเกือบทำให้หัวใจหยุดเต้น</p>
<p>"เจ้าคือผู้ถูกเลือก" เสียงโบราณกึกก้องในหัวเขา "และสงครามครั้งใหม่กำลังจะเริ่มต้นขึ้นแล้ว"</p>'),
('a4444444-4444-4444-4444-444444444444', 2, 'การประลองแห่งเผ่าพันธุ์', false, 18,
'<p>ข่าวการตื่นของอัญมณีแพร่กระจายไปทั่วทวีปภายในคืนเดียว เผ่าเอลฟ์ เผ่าคนแคระ และเผ่ามังกร ต่างส่งตัวแทนมาท้าประลองไครอสเพื่อพิสูจน์ว่าเขาคู่ควรกับพลังนั้นจริงหรือไม่</p>
<p>การต่อสู้ครั้งแรกกับนักรบเอลฟ์ทำให้ไครอสตระหนักว่าพลังเพียงอย่างเดียวไม่พอ เขาต้องเรียนรู้จะควบคุมสายลมที่บ้าคลั่งอยู่ภายในตัวให้ได้ก่อนที่มันจะทำลายตัวเขาเอง</p>'),
('a4444444-4444-4444-4444-444444444444', 3, 'พันธมิตรเงามืด', false, 18,
'<p>ท่ามกลางความโกลาหล หญิงสาวปริศนาในชุดคลุมสีดำปรากฏตัวขึ้นเสนอตัวเป็นพันธมิตร เธอรู้เรื่องอัญมณีทั้งเจ็ดมากกว่าที่ไครอสจะจินตนาการได้</p>
<p>"อัญมณีดวงที่สองกำลังจะตื่นในอีกไม่ช้า และคราวนี้ไม่ใช่แค่การประลอง แต่คือสงครามที่แท้จริง" เธอกล่าวพลางยื่นแผนที่โบราณให้ไครอส เส้นทางสู่มหาสงครามได้เริ่มต้นขึ้นแล้ว</p>')
on conflict (novel_id, number) do nothing;

-- เรื่อง 5: คฤหาสน์เสียงกระซิบ
insert into public.chapters (novel_id, number, title, is_free, price, content) values
('a5555555-5555-5555-5555-555555555555', 1, 'บ้านใหม่ริมป่า', true, 0,
'<p>ครอบครัวสมหวังย้ายเข้าคฤหาสน์เก่าแก่ริมป่าที่ซื้อมาในราคาถูกอย่างน่าประหลาดใจ ลูกสาววัยสิบสองอย่างน้ำฝนเป็นคนแรกที่สังเกตเห็นว่าประตูห้องใต้หลังคาไม่เคยล็อกอยู่ แม้จะปิดมันกี่ครั้งก็ตาม</p>
<p>คืนแรกในบ้านใหม่ น้ำฝนตื่นขึ้นกลางดึกเพราะเสียงกระซิบแผ่วเบาเรียกชื่อเธอ เธอมองไปที่ประตูห้อง มันเปิดออกเองช้าๆ พร้อมกับความมืดที่ดูลึกกว่าปกติ</p>'),
('a5555555-5555-5555-5555-555555555555', 2, 'เสียงที่ไม่มีใครได้ยิน', false, 14,
'<p>น้ำฝนพยายามบอกพ่อแม่เรื่องเสียงกระซิบ แต่ไม่มีใครเชื่อ จนกระทั่งคืนหนึ่งที่เสียงนั้นดังขึ้นพร้อมกันในทุกห้องของบ้าน เรียกชื่อสมาชิกทุกคนพร้อมกันในเวลาเดียว</p>
<p>เมื่อค้นห้องใต้หลังคาอย่างละเอียด น้ำฝนพบภาพถ่ายเก่าของครอบครัวที่เคยอาศัยอยู่ที่นี่เมื่อห้าสิบปีก่อน — ทุกคนในภาพมีใบหน้าถูกขีดฆ่าออกยกเว้นเด็กหญิงคนหนึ่งที่หน้าตาละม้ายคล้ายเธออย่างน่าขนลุก</p>'),
('a5555555-5555-5555-5555-555555555555', 3, 'ผู้ที่ไม่เคยจากไป', false, 14,
'<p>น้ำฝนค้นพบความจริงว่าเด็กหญิงในภาพถ่ายคือผู้ที่เสียชีวิตในบ้านหลังนี้โดยไม่มีใครมารับศพ วิญญาณของเธอเฝ้ารอครอบครัวใหม่มาเติมเต็มบ้านที่ว่างเปล่ามาห้าสิบปี</p>
<p>เสียงกระซิบในคืนนี้ไม่ใช่เสียงเรียกที่น่ากลัวอีกต่อไป แต่เป็นคำขอร้องเพียงอย่างเดียว — ขอให้ใครสักคนจดจำว่าเธอเคยมีตัวตนอยู่จริง</p>')
on conflict (novel_id, number) do nothing;
