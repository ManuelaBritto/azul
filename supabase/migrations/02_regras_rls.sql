-- =====================================================================
-- Azul em Sintonia — 02_regras_rls.sql
-- Regras de acesso (Row Level Security) — equivalentes às firestore.rules.
-- Rode DEPOIS do 01_estrutura.sql. Pode rodar de novo sem problema.
-- Princípio: tudo negado por padrão; cada leitura é liberada por conta,
-- organização, área e papel. Escritas operacionais só passam pelas
-- funções create_incident e register_incident_update, que validam tudo.
-- =====================================================================

-- 1) Liga RLS em todas as tabelas -------------------------------------
alter table public.profiles         enable row level security;
alter table public.organizations    enable row level security;
alter table public.areas            enable row level security;
alter table public.memberships      enable row level security;
alter table public.flights          enable row level security;
alter table public.customer_flights enable row level security;
alter table public.incidents        enable row level security;
alter table public.boards           enable row level security;
alter table public.internal_updates enable row level security;
alter table public.area_status      enable row level security;
alter table public.public_updates   enable row level security;

-- 2) Privilégios: visitante (anon) não lê nada; usuário logado só lê,
--    exceto a própria lista de voos acompanhados -----------------------
revoke all on public.profiles, public.organizations, public.areas, public.memberships, public.flights,
              public.customer_flights, public.incidents, public.boards, public.internal_updates,
              public.area_status, public.public_updates
  from anon, authenticated;

grant select on public.profiles, public.organizations, public.areas, public.memberships, public.flights,
                public.customer_flights, public.incidents, public.boards, public.internal_updates,
                public.area_status, public.public_updates
  to authenticated;
grant insert, delete on public.customer_flights to authenticated;

-- Funções: só usuários logados podem chamar
revoke execute on function public.create_incident(text, text, text, text, text, text, text[]) from public, anon;
revoke execute on function public.register_incident_update(uuid, text, text, text, text, text, timestamptz) from public, anon;
grant  execute on function public.create_incident(text, text, text, text, text, text, text[]) to authenticated;
grant  execute on function public.register_incident_update(uuid, text, text, text, text, text, timestamptz) to authenticated;
revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- 3) Políticas --------------------------------------------------------

-- profiles: cada um lê apenas o próprio perfil (criado pelo gatilho)
drop policy if exists "perfil: ler o próprio" on public.profiles;
create policy "perfil: ler o próprio" on public.profiles
  for select to authenticated
  using (id = (select auth.uid()));

-- memberships: cada funcionário lê apenas os próprios vínculos
drop policy if exists "vínculo: ler o próprio" on public.memberships;
create policy "vínculo: ler o próprio" on public.memberships
  for select to authenticated
  using (user_id = (select auth.uid()));

-- organizations: somente quem tem vínculo ativo
drop policy if exists "organização: membros" on public.organizations;
create policy "organização: membros" on public.organizations
  for select to authenticated
  using (public.has_membership(id));

-- areas: áreas do credenciamento (ou todas, se can_view_all)
drop policy if exists "área: autorizadas" on public.areas;
create policy "área: autorizadas" on public.areas
  for select to authenticated
  using (public.can_access_area(org_id, id));

-- boards: quadro visível para quem acessa a área
drop policy if exists "quadro: área autorizada" on public.boards;
create policy "quadro: área autorizada" on public.boards
  for select to authenticated
  using (public.can_access_area(org_id, area_id));

-- incidents: CCO/admin (can_view_all) ou áreas atribuídas
drop policy if exists "ocorrência: áreas envolvidas" on public.incidents;
create policy "ocorrência: áreas envolvidas" on public.incidents
  for select to authenticated
  using (public.can_read_incident_row(organization_id, assigned_area_ids));

-- internal_updates: histórico interno — só quem lê a ocorrência
drop policy if exists "histórico interno: áreas envolvidas" on public.internal_updates;
create policy "histórico interno: áreas envolvidas" on public.internal_updates
  for select to authenticated
  using (public.can_read_incident(incident_id));

-- area_status: estado por área — só quem lê a ocorrência
drop policy if exists "estado da área: áreas envolvidas" on public.area_status;
create policy "estado da área: áreas envolvidas" on public.area_status
  for select to authenticated
  using (public.can_read_incident(incident_id));

-- flights: catálogo de voos visível a qualquer conta logada
drop policy if exists "voos: contas logadas" on public.flights;
create policy "voos: contas logadas" on public.flights
  for select to authenticated
  using (true);

-- customer_flights: o cliente lê, adiciona e remove somente os seus
drop policy if exists "voos do cliente: ler" on public.customer_flights;
create policy "voos do cliente: ler" on public.customer_flights
  for select to authenticated
  using (user_id = (select auth.uid()) and public.is_customer());

drop policy if exists "voos do cliente: adicionar" on public.customer_flights;
create policy "voos do cliente: adicionar" on public.customer_flights
  for insert to authenticated
  with check (user_id = (select auth.uid()) and public.is_customer() and flight_key ~ '^[A-Z0-9]{4,12}$');

drop policy if exists "voos do cliente: remover" on public.customer_flights;
create policy "voos do cliente: remover" on public.customer_flights
  for delete to authenticated
  using (user_id = (select auth.uid()) and public.is_customer());

-- public_updates: cliente que acompanha o voo, ou equipe que lê a ocorrência.
-- O passageiro nunca acessa incidents/internal_updates/area_status.
drop policy if exists "comunicado público: passageiro ou equipe" on public.public_updates;
create policy "comunicado público: passageiro ou equipe" on public.public_updates
  for select to authenticated
  using (
    (public.is_customer() and public.follows_flight(flight_key))
    or public.can_read_incident(incident_id)
  );

-- 4) Tempo real (substitui o onSnapshot do Firestore) -----------------
--    O Realtime respeita as políticas acima: cada pessoa só recebe o que pode ler.
do $$
declare t text;
begin
  if not exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    create publication supabase_realtime;
  end if;
  foreach t in array array['boards', 'internal_updates', 'area_status', 'public_updates', 'incidents'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public' and tablename = t
    ) then
      execute format('alter publication supabase_realtime add table public.%I', t);
    end if;
  end loop;
end $$;
