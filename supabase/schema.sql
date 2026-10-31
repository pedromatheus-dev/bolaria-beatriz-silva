-- =====================================================================
-- Bolaria Entregas - esquema do banco (Supabase / Postgres)
-- Cole tudo no SQL Editor do Supabase e clique em "Run".
-- =====================================================================

-- ---------- Tabelas ----------
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null,
  papel text not null check (papel in ('admin', 'courier'))
);

create table public.products (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  preco numeric(10,2) not null check (preco >= 0),
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);

create table public.deliveries (
  id uuid primary key default gen_random_uuid(),
  requested_at timestamptz not null default now(),   -- data da solicitação
  scheduled_at timestamptz not null,                 -- dia e hora da entrega
  cliente text not null,
  endereco text not null,
  telefone text,
  observacoes text,
  status text not null default 'pendente'
    check (status in ('pendente', 'aceita', 'concluida', 'cancelada')),
  total numeric(10,2) not null default 0,
  accepted_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now()
);

-- Cópia do nome e do preço no momento do pedido (pedidos antigos não mudam
-- se o preço do produto for alterado depois).
create table public.delivery_items (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  nome text not null,
  preco_unit numeric(10,2) not null,
  quantidade int not null check (quantidade > 0)
);

create index on public.deliveries (scheduled_at);
create index on public.delivery_items (delivery_id);

-- Tabela inofensiva, de leitura pública, usada só pelo "ping" diário.
create table public.health (id int primary key);
insert into public.health values (1);

-- ---------- Funções auxiliares de papel ----------
create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and papel = 'admin');
$$;

create or replace function public.is_courier() returns boolean
language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.profiles where id = auth.uid() and papel = 'courier');
$$;

-- ---------- Segurança por linha (RLS) ----------
alter table public.profiles       enable row level security;
alter table public.products       enable row level security;
alter table public.deliveries     enable row level security;
alter table public.delivery_items enable row level security;
alter table public.health         enable row level security;

create policy profiles_proprio on public.profiles
  for select to authenticated using (id = auth.uid() or public.is_admin());

create policy products_admin on public.products
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create policy deliveries_admin on public.deliveries
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy deliveries_courier_le on public.deliveries
  for select to authenticated using (public.is_courier());

create policy items_admin on public.delivery_items
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy items_courier_le on public.delivery_items
  for select to authenticated using (public.is_courier());

create policy health_publico on public.health
  for select to anon, authenticated using (true);

-- O entregador NÃO tem permissão de update/insert/delete nas tabelas.
-- Ele só muda o status pelas funções abaixo.

-- ---------- Funções de negócio ----------
create or replace function public.criar_entrega(
  p_cliente text, p_endereco text, p_telefone text, p_obs text,
  p_requested_at timestamptz, p_scheduled_at timestamptz, p_itens jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Sem permissão'; end if;
  if p_itens is null or jsonb_array_length(p_itens) = 0 then
    raise exception 'Pedido sem itens';
  end if;

  insert into public.deliveries (requested_at, scheduled_at, cliente, endereco, telefone, observacoes)
  values (coalesce(p_requested_at, now()), p_scheduled_at, p_cliente, p_endereco,
          nullif(p_telefone, ''), nullif(p_obs, ''))
  returning id into v_id;

  -- Nome e preço vêm da tabela de produtos (o app não define preço).
  insert into public.delivery_items (delivery_id, nome, preco_unit, quantidade)
  select v_id, p.nome, p.preco, (i->>'qtd')::int
  from jsonb_array_elements(p_itens) i
  join public.products p on p.id = (i->>'product_id')::uuid
  where (i->>'qtd')::int > 0;

  update public.deliveries
     set total = (select coalesce(sum(preco_unit * quantidade), 0)
                    from public.delivery_items where delivery_id = v_id)
   where id = v_id;

  return v_id;
end $$;

create or replace function public.aceitar_entrega(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_courier() then raise exception 'Sem permissão'; end if;
  update public.deliveries set status = 'aceita', accepted_at = now()
   where id = p_id and status = 'pendente';
  if not found then raise exception 'Entrega indisponível para aceite'; end if;
end $$;

create or replace function public.concluir_entrega(p_id uuid) returns void
language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_courier() then raise exception 'Sem permissão'; end if;
  update public.deliveries set status = 'concluida', completed_at = now()
   where id = p_id and status = 'aceita';
  if not found then raise exception 'Entrega precisa estar aceita'; end if;
end $$;

-- Só usuários logados podem chamar as funções de negócio.
revoke execute on function public.criar_entrega(text,text,text,text,timestamptz,timestamptz,jsonb) from public, anon;
revoke execute on function public.aceitar_entrega(uuid)  from public, anon;
revoke execute on function public.concluir_entrega(uuid) from public, anon;
grant execute on function public.criar_entrega(text,text,text,text,timestamptz,timestamptz,jsonb) to authenticated;
grant execute on function public.aceitar_entrega(uuid)  to authenticated;
grant execute on function public.concluir_entrega(uuid) to authenticated;

-- ---------- Tempo real (a lista atualiza sozinha) ----------
alter publication supabase_realtime add table public.deliveries;

-- Depois deste arquivo, rode também supabase/migracao_v2.sql
