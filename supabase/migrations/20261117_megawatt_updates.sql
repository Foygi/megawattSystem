-- Megawatt Gestão: histórico de pesagens, limpeza automática e Realtime.
-- Execute no SQL Editor do Supabase antes de publicar a nova versão.

create table if not exists public.wire_weighings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete set null,
  username text not null,
  display_name text not null,
  gauge text not null,
  weight_kg numeric(12,3) not null check (weight_kg > 0),
  meters numeric(14,2) not null check (meters > 0),
  created_at timestamptz not null default now()
);
create index if not exists wire_weighings_created_at_idx on public.wire_weighings(created_at desc);
create index if not exists wire_weighings_user_id_idx on public.wire_weighings(user_id, created_at desc);

alter table public.wire_weighings enable row level security;
drop policy if exists "Authenticated users can read wire weighings" on public.wire_weighings;
create policy "Authenticated users can read wire weighings" on public.wire_weighings
  for select to authenticated using (true);
drop policy if exists "Authenticated users can add own wire weighings" on public.wire_weighings;
create policy "Authenticated users can add own wire weighings" on public.wire_weighings
  for insert to authenticated with check (user_id = auth.uid());
drop policy if exists "Admins can delete wire weighings" on public.wire_weighings;
create policy "Admins can delete wire weighings" on public.wire_weighings
  for delete to authenticated using (public.current_user_is_admin());
grant select, insert, delete on public.wire_weighings to authenticated;
alter table public.wire_weighings replica identity full;

create or replace function public.cleanup_old_wire_weighings()
returns integer
language plpgsql
security definer
set search_path = public
as $$
declare removed integer;
begin
  delete from public.wire_weighings where created_at < now() - interval '24 hours';
  get diagnostics removed = row_count;
  return removed;
end;
$$;
revoke all on function public.cleanup_old_wire_weighings() from public;
grant execute on function public.cleanup_old_wire_weighings() to authenticated;

-- Limpa registros expirados sempre que uma nova pesagem é lançada.
create or replace function public.prune_wire_weighings_before_insert()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  delete from public.wire_weighings where created_at < now() - interval '24 hours';
  return null;
end;
$$;
drop trigger if exists trg_prune_wire_weighings on public.wire_weighings;
create trigger trg_prune_wire_weighings before insert on public.wire_weighings
for each statement execute function public.prune_wire_weighings_before_insert();

-- Habilita eventos do registro compartilhado para sincronização entre sessões.
do $$
begin
  begin alter publication supabase_realtime add table public.workspace_state; exception when duplicate_object then null; when undefined_object then null; end;
  begin alter publication supabase_realtime add table public.wire_weighings; exception when duplicate_object then null; when undefined_object then null; end;
end $$;

-- Tarefas em linhas independentes: evita que dois usuários sobrescrevam
-- toda a lista ao criar/alterar tarefas simultaneamente.
create table if not exists public.workspace_tasks (
  id text primary key,
  data jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id) on delete set null
);
insert into public.workspace_tasks (id, data)
select item->>'id', item
from public.workspace_state s,
     lateral jsonb_array_elements(coalesce(s.data->'tasks','[]'::jsonb)) as item
where s.id='main' and item->>'id' is not null
on conflict (id) do nothing;

alter table public.workspace_tasks enable row level security;
drop policy if exists "Authenticated users can read tasks" on public.workspace_tasks;
create policy "Authenticated users can read tasks" on public.workspace_tasks
  for select to authenticated using (true);
drop policy if exists "Editors can insert tasks" on public.workspace_tasks;
create policy "Editors can insert tasks" on public.workspace_tasks
  for insert to authenticated with check (public.current_user_can_edit_workspace());
drop policy if exists "Editors can update tasks" on public.workspace_tasks;
create policy "Editors can update tasks" on public.workspace_tasks
  for update to authenticated using (public.current_user_can_edit_workspace())
  with check (public.current_user_can_edit_workspace());
drop policy if exists "Editors can delete tasks" on public.workspace_tasks;
create policy "Editors can delete tasks" on public.workspace_tasks
  for delete to authenticated using (public.current_user_can_edit_workspace());
grant select, insert, update, delete on public.workspace_tasks to authenticated;
alter table public.workspace_tasks replica identity full;
do $$
begin
  alter publication supabase_realtime add table public.workspace_tasks;
exception when duplicate_object then null;
when undefined_object then null;
end $$;


-- Tabela de referência separada: somente administradores podem alterar os fatores.
create table if not exists public.wire_reference (
  id uuid primary key default gen_random_uuid(),
  product_type text not null default 'Geral',
  gauge text not null,
  reference_weight numeric(12,3) check (reference_weight is null or reference_weight > 0),
  reference_meters numeric(14,2) check (reference_meters is null or reference_meters > 0),
  updated_at timestamptz not null default now()
);
insert into public.wire_reference (product_type, gauge, reference_weight, reference_meters)
select coalesce(nullif(item->>'type',''),'Geral'), item->>'gauge',
       case when coalesce(item->>'referenceWeight','') ~ '^[0-9]+(\.[0-9]+)?$' then (item->>'referenceWeight')::numeric else null end,
       case when coalesce(item->>'referenceMeters','') ~ '^[0-9]+(\.[0-9]+)?$' then (item->>'referenceMeters')::numeric else null end
from public.workspace_state s,
     lateral jsonb_array_elements(coalesce(s.data->'wireReference','[]'::jsonb)) as item
where s.id='main' and coalesce(item->>'gauge','')<>''
  and not exists (select 1 from public.wire_reference wr where wr.product_type=coalesce(nullif(item->>'type',''),'Geral') and wr.gauge=item->>'gauge');
alter table public.wire_reference enable row level security;
drop policy if exists "Authenticated users can read wire reference" on public.wire_reference;
create policy "Authenticated users can read wire reference" on public.wire_reference
  for select to authenticated using (true);
drop policy if exists "Admins can insert wire reference" on public.wire_reference;
create policy "Admins can insert wire reference" on public.wire_reference
  for insert to authenticated with check (public.current_user_is_admin());
drop policy if exists "Admins can update wire reference" on public.wire_reference;
create policy "Admins can update wire reference" on public.wire_reference
  for update to authenticated using (public.current_user_is_admin()) with check (public.current_user_is_admin());
drop policy if exists "Admins can delete wire reference" on public.wire_reference;
create policy "Admins can delete wire reference" on public.wire_reference
  for delete to authenticated using (public.current_user_is_admin());
grant select, insert, update, delete on public.wire_reference to authenticated;
alter table public.wire_reference replica identity full;
do $$
begin
  begin alter publication supabase_realtime add table public.wire_reference; exception when duplicate_object then null; when undefined_object then null; end;
end $$;

-- Agendamento de limpeza a cada cinco minutos (quando pg_cron estiver habilitado no projeto).
do $$
begin
  begin
    create extension if not exists pg_cron with schema pg_catalog;
  exception when others then
    raise notice 'pg_cron não disponível; a limpeza também será executada ao abrir a página e ao lançar pesagens.';
  end;
  begin
    execute $job$
      select cron.unschedule(jobid) from cron.job where jobname = 'megawatt-clean-wire-weighings'
    $job$;
    execute $job$
      select cron.schedule('megawatt-clean-wire-weighings', '*/5 * * * *', 'select public.cleanup_old_wire_weighings();')
    $job$;
  exception when others then
    raise notice 'Não foi possível agendar pg_cron; a limpeza será executada pela aplicação.';
  end;
end $$;
