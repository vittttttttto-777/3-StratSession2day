-- Копия миграции из репозитория ValueStreams-CCI (справочник функций живёт там). Уже применено к проекту awwhrlenhqoreagzfymn 27.09.2026.
-- Тип функции из анкеты «Тип функции» (день 2): центр дохода / сервиса / экспертизы.
-- Нужен для построения структуры по типам функций (Адизес) и для связи с деревом бизнес-метрик.
alter table public.vs_functions add column if not exists fn_type text;
alter table public.vs_functions add column if not exists fn_type_note text;
alter table public.vs_functions drop constraint if exists vs_functions_fn_type_chk;
alter table public.vs_functions add constraint vs_functions_fn_type_chk
  check (fn_type is null or fn_type in ('income','service','expert'));
comment on column public.vs_functions.fn_type is 'Тип функции по анкете дня 2: income = центр дохода, service = центр сервиса, expert = центр экспертизы';
comment on column public.vs_functions.fn_type_note is 'Обоснование типа из анкеты';

-- Дерево бизнес-метрик дня 2 в плоском виде: одна строка = одна метрика.
-- Узел дерева (strat3_trees.tree): {id, n, ne, k:'b'|'o', op:'mul'|'add', g, sg, own, fo, fi:[..], c:[..]}
--   fo  — id функции-владельца из vs_functions
--   fi  — id функций, которые влияют на метрику
--   own — владелец свободным текстом (старые деревья, до связи со справочником)
create or replace view public.strat3_tree_metrics with (security_invoker = true) as
with recursive t as (
  select s.slot, s.tree as node, null::text as parent_id, 0 as lvl,
         (s.tree->>'n') as path, lpad('1', 4, '0') as ord
  from public.strat3_trees s
  union all
  select t.slot, ch.node, t.node->>'id', t.lvl + 1,
         t.path || ' › ' || (ch.node->>'n'),
         t.ord || '.' || lpad(ch.i::text, 4, '0')
  from t
  cross join lateral jsonb_array_elements(coalesce(t.node->'c', '[]'::jsonb)) with ordinality as ch(node, i)
)
select t.slot,
       t.ord                                         as sort_key,
       t.lvl                                         as level,
       t.node->>'id'                                 as node_id,
       t.parent_id,
       t.node->>'n'                                  as metric,
       t.node->>'ne'                                 as metric_en,
       case t.node->>'k' when 'o' then 'операционная' else 'бизнес' end as metric_kind,
       t.path,
       jsonb_array_length(coalesce(t.node->'c','[]'::jsonb)) = 0 as is_leaf,
       case when jsonb_array_length(coalesce(t.node->'c','[]'::jsonb)) = 0 then null
            when t.node->>'op' = 'add' then 'сумма' else 'произведение' end as formula,
       nullif(t.node->>'g','')::numeric              as growth_input_pct,
       t.node->>'fo'                                 as owner_function_id,
       coalesce(fo.name, nullif(t.node->>'own',''))  as owner_function,
       fo.fn_type                                    as owner_fn_type,
       (select string_agg(f.name, ', ' order by f.sort)
          from jsonb_array_elements_text(coalesce(t.node->'fi','[]'::jsonb)) x(fid)
          join public.vs_functions f on f.id = x.fid) as influencing_functions
from t
left join public.vs_functions fo on fo.id = t.node->>'fo';

grant select on public.strat3_tree_metrics to anon, authenticated;
comment on view public.strat3_tree_metrics is 'Деревья бизнес-метрик дня 2 построчно: метрика, формула, владелец и влияющие функции из справочника vs_functions';
