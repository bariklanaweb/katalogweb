-- =========================================================
-- BARIKLANA - SUPABASE DATABASE
-- Jalankan SELURUH file ini di Supabase > SQL Editor > New query.
-- Admin menggunakan Supabase Auth; gambar masih disimpan sebagai data URL di database.
-- File JPG/JPEG diproses browser menjadi data:image/jpeg;base64 dan disimpan pada kolom image_url; pengguna tidak perlu memasukkan URL.
-- =========================================================

begin;

create extension if not exists pgcrypto;

-- 1. TABEL UTAMA
create table if not exists public.stores (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  whatsapp text not null,
  address text not null,
  image_url text,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id) on delete cascade,
  name text not null,
  price numeric(14,2) not null default 0 check (price >= 0),
  stock integer not null default 0 check (stock >= 0),
  image_url text,
  category text,
  is_featured boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  is_active boolean not null default true,
  created_at timestamptz not null default now()
);

-- Banner promo disimpan di database agar tampil sama pada semua perangkat/link.
-- Slot 1-3 membatasi jumlah banner dan menjaga urutannya.
create table if not exists public.banners (
  slot integer primary key check (slot between 1 and 3),
  image_url text not null,
  updated_at timestamptz not null default now()
);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(),
  store_id uuid not null references public.stores(id),
  customer_name text not null,
  customer_address text,
  total numeric(14,2) not null default 0,
  status text not null default 'baru',
  created_at timestamptz not null default now()
);

create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid not null references public.products(id),
  product_name text not null,
  quantity integer not null check (quantity > 0),
  unit_price numeric(14,2) not null check (unit_price >= 0),
  subtotal numeric(14,2) not null check (subtotal >= 0)
);

-- 2. MIGRASI AMAN: menambahkan kolom yang mungkin belum ada
-- jika tabel sudah pernah dibuat pada versi SQL sebelumnya.
alter table public.stores
  add column if not exists name text,
  add column if not exists whatsapp text,
  add column if not exists address text,
  add column if not exists image_url text,
  add column if not exists description text,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamptz not null default now();

alter table public.products
  add column if not exists store_id uuid,
  add column if not exists name text,
  add column if not exists price numeric(14,2) not null default 0,
  add column if not exists stock integer not null default 0,
  add column if not exists image_url text,
  add column if not exists category text,
  add column if not exists is_featured boolean not null default false,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamptz not null default now();

alter table public.orders
  add column if not exists store_id uuid,
  add column if not exists customer_name text,
  add column if not exists customer_address text,
  add column if not exists total numeric(14,2) not null default 0,
  add column if not exists status text not null default 'baru',
  add column if not exists created_at timestamptz not null default now();

alter table public.order_items
  add column if not exists order_id uuid,
  add column if not exists product_id uuid,
  add column if not exists product_name text,
  add column if not exists quantity integer,
  add column if not exists unit_price numeric(14,2),
  add column if not exists subtotal numeric(14,2);

-- 3. MIGRASI KATEGORI
-- Menjamin kolom tersedia jika tabel categories pernah dibuat pada versi lama.
alter table public.categories
  add column if not exists name text,
  add column if not exists is_active boolean not null default true,
  add column if not exists created_at timestamptz not null default now();

-- 4. INDEX
create index if not exists idx_categories_active_name on public.categories(is_active, name);
create index if not exists idx_products_store_id on public.products(store_id);
create index if not exists idx_products_active_created on public.products(is_active, created_at desc);
create index if not exists idx_stores_active_created on public.stores(is_active, created_at desc);
create index if not exists idx_orders_created on public.orders(created_at desc);
create index if not exists idx_order_items_order_id on public.order_items(order_id);

-- 5. RLS DAN AUTHENTICATION ADMIN
-- PENTING: hapus SEMUA policy lama pada tabel aplikasi ini terlebih dahulu.
-- Policy PostgreSQL bersifat permissive (OR); policy lama yang tertinggal dapat
-- membuka akses meskipun policy baru sudah dibuat. Langkah ini membuat migrasi
-- keamanan konsisten pada proyek yang pernah memakai SQL versi sebelumnya.
do $$
declare
  v_table text;
  v_policy record;
begin
  foreach v_table in array array[
    'stores','products','categories','banners','orders','order_items','admin_users'
  ] loop
    for v_policy in
      select policyname
      from pg_policies
      where schemaname = 'public' and tablename = v_table
    loop
      execute format('drop policy if exists %I on public.%I', v_policy.policyname, v_table);
    end loop;
  end loop;
end;
$$;
-- Katalog tetap dapat dibaca publik. Perubahan data hanya untuk user Supabase Auth
-- yang UID-nya terdaftar pada public.admin_users.
create table if not exists public.admin_users (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);
alter table public.admin_users enable row level security;

create or replace function public.is_bariklana_admin()
returns boolean
language sql
stable
security definer
set search_path = public, auth, pg_temp
as $$
  select exists (
    select 1 from public.admin_users
    where user_id = auth.uid()
  );
$$;
revoke all on function public.is_bariklana_admin() from public, anon;
grant execute on function public.is_bariklana_admin() to authenticated;

drop policy if exists "Admin can read own admin record" on public.admin_users;
create policy "Admin can read own admin record" on public.admin_users
  for select to authenticated using (user_id = auth.uid());

alter table public.stores enable row level security;
alter table public.products enable row level security;
alter table public.categories enable row level security;
alter table public.banners enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

-- Public catalog read
drop policy if exists "Bariklana public stores read" on public.stores;
create policy "Bariklana public stores read" on public.stores
  for select to anon, authenticated using (true);
drop policy if exists "Bariklana public banners read" on public.banners;
create policy "Bariklana public banners read" on public.banners
  for select to anon, authenticated using (true);
drop policy if exists "Bariklana public categories read" on public.categories;
create policy "Bariklana public categories read" on public.categories
  for select to anon, authenticated using (true);
drop policy if exists "Bariklana public products read" on public.products;
create policy "Bariklana public products read" on public.products
  for select to anon, authenticated using (true);

-- Admin-only writes for catalog data
drop policy if exists "Bariklana app stores write" on public.stores;
create policy "Bariklana admin stores write" on public.stores
  for all to authenticated using (public.is_bariklana_admin())
  with check (public.is_bariklana_admin());
drop policy if exists "Bariklana app banners write" on public.banners;
create policy "Bariklana admin banners write" on public.banners
  for all to authenticated using (public.is_bariklana_admin())
  with check (public.is_bariklana_admin());
drop policy if exists "Bariklana app categories write" on public.categories;
create policy "Bariklana admin categories write" on public.categories
  for all to authenticated using (public.is_bariklana_admin())
  with check (public.is_bariklana_admin());
drop policy if exists "Bariklana app products write" on public.products;
create policy "Bariklana admin products write" on public.products
  for all to authenticated using (public.is_bariklana_admin())
  with check (public.is_bariklana_admin());

-- Order history visible only to Admin. Customer checkout still uses the
-- SECURITY DEFINER RPC below, so guests can submit orders without table write access.
drop policy if exists "Bariklana app orders read" on public.orders;
create policy "Bariklana admin orders read" on public.orders
  for select to authenticated using (public.is_bariklana_admin());
drop policy if exists "Bariklana app orders insert" on public.orders;
drop policy if exists "Bariklana app order items read" on public.order_items;
create policy "Bariklana admin order items read" on public.order_items
  for select to authenticated using (public.is_bariklana_admin());
drop policy if exists "Bariklana app order items insert" on public.order_items;

revoke all on public.stores, public.products, public.categories, public.banners, public.orders, public.order_items, public.admin_users from anon;
revoke all on public.orders, public.order_items, public.admin_users from authenticated;
grant usage on schema public to anon, authenticated;
grant select on public.stores, public.products, public.categories, public.banners to anon, authenticated;
grant insert, update, delete on public.stores, public.products, public.categories, public.banners to authenticated;
grant select on public.orders, public.order_items to authenticated;
grant select on public.admin_users to authenticated;

-- 6. CHECKOUT ATOMIK + PENGURANGAN STOK
-- Function dibuat SEBELUM GRANT EXECUTE (memperbaiki error urutan SQL lama).
create or replace function public.checkout_order(
  p_store_id uuid,
  p_customer_name text,
  p_customer_address text,
  p_items jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_order_id uuid;
  v_item jsonb;
  v_product_id uuid;
  v_qty integer;
  v_name text;
  v_price numeric(14,2);
  v_stock integer;
  v_total numeric(14,2) := 0;
  v_subtotal numeric(14,2);
begin
  if p_store_id is null then
    raise exception 'Toko wajib dipilih';
  end if;

  if nullif(trim(coalesce(p_customer_name, '')), '') is null then
    raise exception 'Nama pemesan wajib diisi';
  end if;

  if p_items is null
     or jsonb_typeof(p_items) is distinct from 'array'
     or jsonb_array_length(p_items) = 0 then
    raise exception 'Keranjang pesanan kosong';
  end if;

  if not exists (
    select 1 from public.stores
    where id = p_store_id and is_active = true
  ) then
    raise exception 'Toko tidak ditemukan atau tidak aktif';
  end if;

  insert into public.orders
    (store_id, customer_name, customer_address, total, status)
  values
    (p_store_id, trim(p_customer_name), coalesce(p_customer_address, ''), 0, 'baru')
  returning id into v_order_id;

  for v_item in
    select value from jsonb_array_elements(p_items)
  loop
    if coalesce(v_item->>'product_id', '') = ''
       or coalesce(v_item->>'quantity', '') !~ '^[0-9]+$' then
      raise exception 'Data produk atau jumlah pesanan tidak valid';
    end if;

    v_product_id := (v_item->>'product_id')::uuid;
    v_qty := (v_item->>'quantity')::integer;

    if v_qty < 1 then
      raise exception 'Jumlah produk minimal 1';
    end if;

    select p.name, p.price, p.stock
      into v_name, v_price, v_stock
      from public.products p
     where p.id = v_product_id
       and p.store_id = p_store_id
       and p.is_active = true
     for update;

    if not found then
      raise exception 'Produk tidak ditemukan atau tidak aktif';
    end if;

    if v_stock < v_qty then
      raise exception 'Stok produk % tidak mencukupi', v_name;
    end if;

    update public.products
       set stock = stock - v_qty
     where id = v_product_id;

    v_subtotal := v_price * v_qty;
    v_total := v_total + v_subtotal;

    insert into public.order_items
      (order_id, product_id, product_name, quantity, unit_price, subtotal)
    values
      (v_order_id, v_product_id, v_name, v_qty, v_price, v_subtotal);
  end loop;

  update public.orders
     set total = v_total
   where id = v_order_id;

  return jsonb_build_object(
    'success', true,
    'order_id', v_order_id,
    'total', v_total
  );
end;
$function$;

revoke all on function public.checkout_order(uuid, text, text, jsonb) from public;
grant execute on function public.checkout_order(uuid, text, text, jsonb) to anon, authenticated;

-- 7. CATATAN KEAMANAN
-- Buat akun Admin di Supabase Authentication > Users (Add user).
-- Setelah akun dibuat, daftarkan UID akun tersebut ke public.admin_users.
-- Jangan aktifkan public sign-ups. Jangan pernah menaruh service_role key di frontend.
-- Hanya UID yang terdaftar pada admin_users yang dapat melakukan perubahan data.
-- Katalog tetap dapat dibaca publik dan checkout tetap dapat dilakukan tanpa login.

commit;

-- CATATAN AKHIR:
-- Aplikasi menggunakan Supabase Auth dan RLS. Jangan pernah menaruh service_role
-- key di frontend. Publishable/anon key memang boleh digunakan di frontend karena
-- hak akses tetap dibatasi oleh grants dan RLS di atas.
