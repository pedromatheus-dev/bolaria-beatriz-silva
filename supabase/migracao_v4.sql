-- =====================================================================
-- Bolaria Beatriz - migração v4  (rode DEPOIS da migracao_v2.sql)
-- Pode rodar de novo sem estragar.
-- Faz: taxa de entrega, combos, histórico (rastreio) das entregas,
--      telefone nos perfis, configuração da taxa.
-- =====================================================================

-- ---------- 1) Perfis: telefone + permissões ----------
alter table public.profiles add column if not exists telefone text;

drop policy if exists profiles_admin_update on public.profiles;
create policy profiles_admin_update on public.profiles
  for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- O entregador precisa enxergar nome/telefone da dona (para avisá-la no WhatsApp)
drop policy if exists profiles_courier_le_admin on public.profiles;
create policy profiles_courier_le_admin on public.profiles
  for select to authenticated
  using (public.is_courier() and papel = 'admin');

-- ---------- 2) Configuração (taxa de entrega) ----------
create table if not exists public.config (
  chave text primary key,
  valor text not null
);
insert into public.config (chave, valor) values ('taxa_entrega', '2.00')
  on conflict (chave) do nothing;
alter table public.config enable row level security;
drop policy if exists config_le on public.config;
drop policy if exists config_admin_update on public.config;
create policy config_le on public.config for select to authenticated using (true);
create policy config_admin_update on public.config
  for update to authenticated using (public.is_admin()) with check (public.is_admin());

-- ---------- 3) Entregas: valor dos produtos + taxa ----------
alter table public.deliveries add column if not exists subtotal numeric(10,2) not null default 0;
alter table public.deliveries add column if not exists taxa_entrega numeric(10,2) not null default 0;
-- entregas antigas: o total antigo vira "produtos" e ficam sem taxa
update public.deliveries set subtotal = total where subtotal = 0 and total > 0;

alter table public.delivery_items add column if not exists tipo text not null default 'produto';
alter table public.delivery_items add column if not exists descricao text;

-- ---------- 4) Combos ----------
create table if not exists public.combos (
  id uuid primary key default gen_random_uuid(),
  nome text not null,
  preco numeric(10,2) not null check (preco >= 0),
  ativo boolean not null default true,
  created_at timestamptz not null default now()
);
create table if not exists public.combo_items (
  combo_id uuid not null references public.combos(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete restrict,
  quantidade int not null check (quantidade > 0),
  primary key (combo_id, product_id)
);
alter table public.combos enable row level security;
alter table public.combo_items enable row level security;
drop policy if exists combos_admin on public.combos;
drop policy if exists combo_items_admin on public.combo_items;
create policy combos_admin on public.combos
  for all to authenticated using (public.is_admin()) with check (public.is_admin());
create policy combo_items_admin on public.combo_items
  for all to authenticated using (public.is_admin()) with check (public.is_admin());

create or replace function public.salvar_combo(
  p_id uuid, p_nome text, p_preco numeric, p_itens jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
begin
  if not public.is_admin() then raise exception 'Sem permissão'; end if;
  if p_itens is null or (select coalesce(sum((i->>'qtd')::int), 0)
                           from jsonb_array_elements(p_itens) i) < 2 then
    raise exception 'O combo precisa ter pelo menos 2 itens';
  end if;

  if p_id is null then
    insert into public.combos (nome, preco) values (p_nome, p_preco) returning id into v_id;
  else
    update public.combos set nome = p_nome, preco = p_preco where id = p_id returning id into v_id;
    if v_id is null then raise exception 'Combo não encontrado'; end if;
    delete from public.combo_items where combo_id = v_id;
  end if;

  insert into public.combo_items (combo_id, product_id, quantidade)
  select v_id, (i->>'product_id')::uuid, (i->>'qtd')::int
    from jsonb_array_elements(p_itens) i
   where (i->>'qtd')::int > 0;

  return v_id;
end $$;

revoke execute on function public.salvar_combo(uuid, text, numeric, jsonb) from public, anon;
grant  execute on function public.salvar_combo(uuid, text, numeric, jsonb) to authenticated;

-- Remove os "combos" que a v2 criou como se fossem produtos
-- (recrie-os na aba Produtos > Combos, depois de cadastrar a Empada).
delete from public.products
 where nome in ('Combo 1 (2 empadas + 1 Delrio 250ml)',
                'Combo 3 (3 empadas + 1 Maria Maluca + 1 Delrio 250ml)');

-- ---------- 5) Histórico (rastreio) ----------
create table if not exists public.delivery_events (
  id uuid primary key default gen_random_uuid(),
  delivery_id uuid not null references public.deliveries(id) on delete cascade,
  tipo text not null,
  descricao text,
  ocorrido_em timestamptz not null default now()
);
create index if not exists delivery_events_delivery_idx on public.delivery_events (delivery_id, ocorrido_em);
alter table public.delivery_events enable row level security;
drop policy if exists events_le on public.delivery_events;
drop policy if exists events_admin_insert on public.delivery_events;
create policy events_le on public.delivery_events
  for select to authenticated using (public.is_admin() or public.is_courier());
create policy events_admin_insert on public.delivery_events
  for insert to authenticated with check (public.is_admin());

-- Histórico das entregas que já existem
with alvo as (
  select * from public.deliveries d
   where not exists (select 1 from public.delivery_events e where e.delivery_id = d.id)
)
insert into public.delivery_events (delivery_id, tipo, descricao, ocorrido_em)
select id, 'solicitada', 'Pedido solicitado pelo cliente', requested_at from alvo
union all select id, 'cadastrada', 'Entrega cadastrada no app', created_at from alvo
union all select id, 'aceita', 'Aceita pelo entregador', accepted_at from alvo where accepted_at is not null
union all select id, 'concluida', 'Entrega concluída', completed_at from alvo where completed_at is not null
union all select id, 'cancelada', 'Entrega cancelada', created_at from alvo where status = 'cancelada';

create or replace function public.registrar_eventos_entrega() returns trigger
language plpgsql security definer set search_path = '' as $$
declare
  v_min int;
  v_abs int;
  v_txt text;
begin
  if tg_op = 'INSERT' then
    insert into public.delivery_events (delivery_id, tipo, descricao, ocorrido_em) values
      (new.id, 'solicitada', 'Pedido solicitado pelo cliente', new.requested_at),
      (new.id, 'cadastrada', 'Entrega cadastrada no app', now());
  elsif new.status is distinct from old.status then
    if new.status = 'aceita' then
      insert into public.delivery_events (delivery_id, tipo, descricao, ocorrido_em)
      values (new.id, 'aceita', 'Aceita pelo entregador', coalesce(new.accepted_at, now()));
    elsif new.status = 'concluida' then
      v_min := round(extract(epoch from (coalesce(new.completed_at, now()) - new.scheduled_at)) / 60)::int;
      v_abs := abs(v_min);
      v_txt := case when v_abs < 60 then v_abs::text || ' min'
                    else (v_abs / 60)::text || ' h ' || lpad((v_abs % 60)::text, 2, '0') || ' min' end;
      insert into public.delivery_events (delivery_id, tipo, descricao, ocorrido_em)
      values (new.id, 'concluida',
        case when v_abs <= 5 then 'Entrega concluída no horário previsto'
             when v_min < 0  then 'Entrega concluída ' || v_txt || ' antes do previsto'
             else 'Entrega concluída com ' || v_txt || ' de atraso' end,
        coalesce(new.completed_at, now()));
    elsif new.status = 'cancelada' then
      insert into public.delivery_events (delivery_id, tipo, descricao, ocorrido_em)
      values (new.id, 'cancelada', 'Entrega cancelada', now());
    end if;
  end if;
  return null;
end $$;

drop trigger if exists trg_eventos_entrega on public.deliveries;
create trigger trg_eventos_entrega
  after insert or update of status on public.deliveries
  for each row execute function public.registrar_eventos_entrega();

-- ---------- 6) Criar entrega (agora com taxa e combos) ----------
drop function if exists public.criar_entrega(text, text, text, text, timestamptz, timestamptz, jsonb);

create or replace function public.criar_entrega(
  p_cliente text, p_endereco text, p_telefone text, p_obs text,
  p_requested_at timestamptz, p_scheduled_at timestamptz,
  p_itens jsonb, p_combos jsonb default '[]'::jsonb
) returns uuid
language plpgsql security definer set search_path = '' as $$
declare
  v_id uuid;
  v_taxa numeric;
  v_sub numeric;
begin
  if not public.is_admin() then raise exception 'Sem permissão'; end if;
  if coalesce(jsonb_array_length(p_itens), 0) + coalesce(jsonb_array_length(p_combos), 0) = 0 then
    raise exception 'Pedido sem itens';
  end if;

  select coalesce((select valor::numeric from public.config where chave = 'taxa_entrega'), 2.00)
    into v_taxa;

  insert into public.deliveries (requested_at, scheduled_at, cliente, endereco, telefone, observacoes, taxa_entrega)
  values (coalesce(p_requested_at, now()), p_scheduled_at, p_cliente, p_endereco,
          nullif(p_telefone, ''), nullif(p_obs, ''), v_taxa)
  returning id into v_id;

  -- Produtos avulsos (nome e preço vêm da tabela de produtos)
  insert into public.delivery_items (delivery_id, nome, preco_unit, quantidade, tipo)
  select v_id, p.nome, p.preco, (i->>'qtd')::int, 'produto'
    from jsonb_array_elements(coalesce(p_itens, '[]'::jsonb)) i
    join public.products p on p.id = (i->>'product_id')::uuid
   where (i->>'qtd')::int > 0;

  -- Combos (nome, preço e composição vêm da tabela de combos)
  insert into public.delivery_items (delivery_id, nome, preco_unit, quantidade, tipo, descricao)
  select v_id, c.nome, c.preco, (i->>'qtd')::int, 'combo',
         (select string_agg(ci.quantidade::text || 'x ' || pr.nome, ' + ' order by pr.nome)
            from public.combo_items ci
            join public.products pr on pr.id = ci.product_id
           where ci.combo_id = c.id)
    from jsonb_array_elements(coalesce(p_combos, '[]'::jsonb)) i
    join public.combos c on c.id = (i->>'combo_id')::uuid
   where (i->>'qtd')::int > 0;

  select coalesce(sum(preco_unit * quantidade), 0) into v_sub
    from public.delivery_items where delivery_id = v_id;

  update public.deliveries set subtotal = v_sub, total = v_sub + v_taxa where id = v_id;
  return v_id;
end $$;

revoke execute on function public.criar_entrega(text,text,text,text,timestamptz,timestamptz,jsonb,jsonb) from public, anon;
grant  execute on function public.criar_entrega(text,text,text,text,timestamptz,timestamptz,jsonb,jsonb) to authenticated;

notify pgrst, 'reload schema';
