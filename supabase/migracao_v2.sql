-- =====================================================================
-- Bolaria Beatriz - migração v2
-- Rode UMA vez no SQL Editor do Supabase (pode rodar de novo sem estragar).
-- Faz: número sequencial da entrega, exclusão de entregas canceladas
--      e cadastro completo dos produtos.
-- =====================================================================

-- ---------- 1) Número sequencial: ddmmaa + 4 dígitos do dia ----------
-- O "dia" é o dia da ENTREGA (scheduled_at), no horário de Fortaleza.
-- Para numerar pelo dia em que o pedido foi cadastrado, troque
-- "new.scheduled_at" por "new.requested_at" na função abaixo
-- (e "scheduled_at" por "requested_at" nos dois blocos de ajuste inicial).

create table if not exists public.delivery_counters (
  dia date primary key,
  ultimo int not null default 0
);
alter table public.delivery_counters enable row level security;  -- sem políticas: só a função interna acessa

alter table public.deliveries add column if not exists numero text;

-- Numera as entregas que já existem (testes, por exemplo)
with t as (
  select id,
         (scheduled_at at time zone 'America/Fortaleza')::date as dia,
         row_number() over (
           partition by (scheduled_at at time zone 'America/Fortaleza')::date
           order by created_at
         ) as n
  from public.deliveries
  where numero is null
)
update public.deliveries d
   set numero = to_char(t.dia, 'DDMMYY') || lpad(t.n::text, 4, '0')
  from t
 where t.id = d.id;

insert into public.delivery_counters (dia, ultimo)
select (scheduled_at at time zone 'America/Fortaleza')::date, count(*)
  from public.deliveries
 group by 1
on conflict (dia) do update
  set ultimo = greatest(public.delivery_counters.ultimo, excluded.ultimo);

alter table public.deliveries alter column numero set not null;
create unique index if not exists deliveries_numero_key on public.deliveries (numero);

create or replace function public.gerar_numero_entrega() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_dia date;
  v_n int;
begin
  v_dia := (new.scheduled_at at time zone 'America/Fortaleza')::date;
  insert into public.delivery_counters as c (dia, ultimo)
  values (v_dia, 1)
  on conflict (dia) do update set ultimo = c.ultimo + 1
  returning ultimo into v_n;
  new.numero := to_char(v_dia, 'DDMMYY') || lpad(v_n::text, 4, '0');
  return new;
end $$;

drop trigger if exists trg_numero_entrega on public.deliveries;
create trigger trg_numero_entrega
  before insert on public.deliveries
  for each row execute function public.gerar_numero_entrega();

-- ---------- 2) Excluir: o dono só apaga entregas CANCELADAS ----------
drop policy if exists deliveries_admin on public.deliveries;
drop policy if exists deliveries_admin_select on public.deliveries;
drop policy if exists deliveries_admin_insert on public.deliveries;
drop policy if exists deliveries_admin_update on public.deliveries;
drop policy if exists deliveries_admin_delete on public.deliveries;

create policy deliveries_admin_select on public.deliveries
  for select to authenticated using (public.is_admin());
create policy deliveries_admin_insert on public.deliveries
  for insert to authenticated with check (public.is_admin());
create policy deliveries_admin_update on public.deliveries
  for update to authenticated using (public.is_admin()) with check (public.is_admin());
create policy deliveries_admin_delete on public.deliveries
  for delete to authenticated using (public.is_admin() and status = 'cancelada');

-- ---------- 3) Produtos ----------
-- Remove os dois produtos de exemplo da versão 1
delete from public.products where nome in ('Bolo (R$ 14)', 'Bolo (R$ 18)');

insert into public.products (nome, preco)
select v.nome, v.preco
from (values
  -- Bolos de R$ 14
  ('Bolo de Laranja',                  14.00),
  ('Bolo de Mesclado',                 14.00),
  ('Bolo de Mole',                     14.00),
  ('Bolo de Milho',                    14.00),
  ('Bolo de Batata',                   14.00),
  ('Bolo de Chocolate',                14.00),
  -- Bolos de R$ 18
  ('Bolo de Choconinho',               18.00),
  ('Bolo de Cenoura com Chocolate',    18.00),
  ('Bolo de Limão',                    18.00),
  ('Bolo de Red Velvet com Ninho',     18.00),
  -- Avulsos
  ('Maria Maluca',                      3.80),
  ('Delrio 250ml',                      3.00),
  -- Combos
  ('Combo 1 (2 empadas + 1 Delrio 250ml)',                        13.00),
  ('Combo 3 (3 empadas + 1 Maria Maluca + 1 Delrio 250ml)',       22.00)
) as v(nome, preco)
where not exists (select 1 from public.products p where p.nome = v.nome);
