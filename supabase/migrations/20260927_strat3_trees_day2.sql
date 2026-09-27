-- Стратсессия №3 · День 2: хранение деревьев метрик и инструмента Елены.
-- Уже применено к проекту awwhrlenhqoreagzfymn 27.09.2026. Файл — для истории и повторного развёртывания.
-- Требует существующих объектов дня 1: public.strat3_admin, public.strat3_check_pin(text), public.strat3_state.

create table if not exists public.strat3_trees (
  slot text primary key,
  tree jsonb not null,
  updated_at timestamptz not null default now()
);
create table if not exists public.strat3_tree_history (
  id bigserial primary key,
  slot text not null,
  tree jsonb not null,
  saved_at timestamptz not null default now()
);
create index if not exists strat3_tree_history_slot_idx on public.strat3_tree_history (slot, saved_at desc);

alter table public.strat3_trees enable row level security;
alter table public.strat3_tree_history enable row level security;
drop policy if exists strat3_trees_read on public.strat3_trees;
create policy strat3_trees_read on public.strat3_trees for select to anon, authenticated using (true);
-- strat3_tree_history: без клиентских политик, доступ только через SQL/service role.

create or replace function public.strat3_tree_save(p_slot text, p_tree jsonb, p_pin text default null)
returns void language plpgsql security definer set search_path to 'public', 'extensions' as $$
begin
  if p_slot not in ('HealthOS','GrowthModel','PrimeGrowth','CoralEVO','ITModel','CCI','elena') then
    raise exception 'unknown slot';
  end if;
  if p_slot in ('CCI','elena') and not public.strat3_check_pin(p_pin) then
    raise exception 'invalid pin' using errcode = '28000';
  end if;
  if p_tree is null or octet_length(p_tree::text) > 200000 then
    raise exception 'tree too large';
  end if;
  insert into public.strat3_trees (slot, tree, updated_at) values (p_slot, p_tree, now())
  on conflict (slot) do update set tree = excluded.tree, updated_at = now();
  if not exists (select 1 from public.strat3_tree_history where slot = p_slot and saved_at > now() - interval '1 minute') then
    insert into public.strat3_tree_history (slot, tree) values (p_slot, p_tree);
  end if;
end; $$;
revoke all on function public.strat3_tree_save(text, jsonb, text) from public;
grant execute on function public.strat3_tree_save(text, jsonb, text) to anon, authenticated;

-- Трансляция на проектор для дня 2 (ключ presenter-d2).
create or replace function public.strat3_save(p_key text, p_value jsonb, p_pin text)
returns void language plpgsql security definer set search_path to 'public', 'extensions' as $$
begin
  if not public.strat3_check_pin(p_pin) then
    raise exception 'invalid pin' using errcode = '28000';
  end if;
  if p_key not in ('schedule', 'seating', 'presenter', 'presenter-d2') then
    raise exception 'unknown key';
  end if;
  insert into public.strat3_state (key, value, updated_at) values (p_key, p_value, now())
  on conflict (key) do update set value = excluded.value, updated_at = now();
end; $$;

alter publication supabase_realtime add table public.strat3_trees;
