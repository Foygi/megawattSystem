-- Megawatt Gestão — esquema inicial do banco Supabase
-- Execute este arquivo no SQL Editor do projeto Supabase.

create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  email text not null unique,
  username text not null,
  display_name text not null,
  role text not null default 'editor' check (role in ('admin', 'editor', 'reader')),
  work jsonb not null default '{"days":[1,2,3,4,5],"start":"08:00","end":"18:00"}'::jsonb,
  preferences jsonb not null default '{"widgets":["stats","urgent","upcoming","quickLinks","summary"],"linkOrder":[],"dashboardOrder":["stats","urgent","upcoming","quickLinks","summary"],"visibleLinks":[]}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username));

create table if not exists public.workspace_state (
  id text primary key check (id = 'main'),
  data jsonb not null default '{"tasks":[],"contacts":[],"links":[],"notes":[],"theme":"light"}'::jsonb,
  updated_at timestamptz not null default now()
);

insert into public.workspace_state (id, data)
values ('main', '{"tasks":[],"contacts":[],"links":[],"notes":[],"theme":"light"}'::jsonb)
on conflict (id) do nothing;

-- Helper com SECURITY DEFINER para consultar o perfil sem recursão de RLS.
create or replace function public.current_user_can_edit_workspace()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role in ('admin', 'editor')
  );
$$;

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.profiles
    where id = auth.uid() and role = 'admin'
  );
$$;

revoke all on function public.current_user_can_edit_workspace() from public;
revoke all on function public.current_user_is_admin() from public;
grant execute on function public.current_user_can_edit_workspace() to authenticated;
grant execute on function public.current_user_is_admin() to authenticated;

alter table public.profiles enable row level security;
alter table public.workspace_state enable row level security;

-- Funcionários autenticados podem consultar os perfis para atribuir tarefas.
drop policy if exists "Authenticated users can read profiles" on public.profiles;
create policy "Authenticated users can read profiles"
  on public.profiles for select to authenticated
  using (true);

-- Cada usuário pode alterar apenas seu nome e preferências pela aplicação.
-- O papel, e-mail, username e expediente são alterados pela Edge Function administrativa.
drop policy if exists "Users can update own basic profile" on public.profiles;
create policy "Users can update own basic profile"
  on public.profiles for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

revoke all on public.profiles from anon, authenticated;
grant select on public.profiles to authenticated;
grant update (display_name, preferences) on public.profiles to authenticated;

-- Todos os usuários autenticados podem consultar os dados compartilhados.
drop policy if exists "Authenticated users can read workspace" on public.workspace_state;
create policy "Authenticated users can read workspace"
  on public.workspace_state for select to authenticated
  using (true);

-- Administradores e editores podem salvar; leitores ficam somente leitura.
drop policy if exists "Editors can insert workspace" on public.workspace_state;
create policy "Editors can insert workspace"
  on public.workspace_state for insert to authenticated
  with check (public.current_user_can_edit_workspace());

drop policy if exists "Editors can update workspace" on public.workspace_state;
create policy "Editors can update workspace"
  on public.workspace_state for update to authenticated
  using (public.current_user_can_edit_workspace())
  with check (public.current_user_can_edit_workspace());

drop policy if exists "Admins can delete workspace" on public.workspace_state;
create policy "Admins can delete workspace"
  on public.workspace_state for delete to authenticated
  using (public.current_user_is_admin());

grant select, insert, update, delete on public.workspace_state to authenticated;

-- O primeiro administrador deve ser cadastrado manualmente em Authentication > Users.
-- Depois, use o SQL de bootstrap descrito no README.md para criar seu perfil admin.
