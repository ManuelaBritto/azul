-- =====================================================================
-- Azul em Sintonia — 01_estrutura.sql
-- Cole no Supabase: SQL Editor → New query → Run.
-- Cria tabelas, funções auxiliares, gatilhos e as funções (RPC) usadas
-- pelo site para criar ocorrências e registrar atualizações.
-- Ordem: 01_estrutura.sql → 02_regras_rls.sql → 03_dados_iniciais.sql
-- =====================================================================

create extension if not exists pgcrypto with schema extensions;

-- ---------------------------------------------------------------------
-- TABELAS
-- ---------------------------------------------------------------------

-- Perfil de cada conta (antes: profiles/{uid})
create table if not exists public.profiles (
  id           uuid primary key references auth.users (id) on delete cascade,
  full_name    text not null default '',
  email        text not null default '',
  account_type text not null default 'customer' check (account_type in ('customer', 'employee')),
  created_at   timestamptz not null default now()
);

-- Organizações (antes: organizations/{orgId})
create table if not exists public.organizations (
  id         text primary key,
  name       text not null,
  created_at timestamptz not null default now()
);

-- Áreas operacionais (antes: organizations/{orgId}/areas/{areaId})
create table if not exists public.areas (
  org_id     text not null references public.organizations (id) on delete cascade,
  id         text not null,
  name       text not null,
  active     boolean not null default true,
  created_at timestamptz not null default now(),
  primary key (org_id, id)
);

-- Credenciamento de funcionários (antes: profiles/{uid}/memberships/{orgId})
create table if not exists public.memberships (
  user_id              uuid not null references auth.users (id) on delete cascade,
  org_id               text not null references public.organizations (id) on delete cascade,
  active               boolean not null default true,
  organization_name    text,
  area_ids             text[] not null default '{}',
  area_names           jsonb  not null default '{}'::jsonb,
  roles                jsonb  not null default '{}'::jsonb,
  can_view_all         boolean not null default false,
  can_manage_incidents boolean not null default false,
  created_at           timestamptz not null default now(),
  primary key (user_id, org_id)
);

-- Catálogo de voos (novo — base para clientes e ocorrências)
create table if not exists public.flights (
  flight_key          text primary key check (flight_key ~ '^[A-Z0-9]{4,12}$'),
  flight_code         text not null,
  origin              text not null,
  origin_city         text,
  destination         text not null,
  destination_city    text,
  scheduled_departure timestamptz,
  scheduled_arrival   timestamptz,
  aircraft            text,
  created_at          timestamptz not null default now()
);

-- Voos acompanhados pelo cliente (antes: profiles/{uid}/customerFlights/{flightKey})
create table if not exists public.customer_flights (
  user_id     uuid not null references auth.users (id) on delete cascade,
  flight_key  text not null references public.flights (flight_key) on delete cascade
              check (flight_key ~ '^[A-Z0-9]{4,12}$'),
  flight_code text not null,
  created_at  timestamptz not null default now(),
  primary key (user_id, flight_key)
);

-- Ocorrências (antes: incidents/{incidentId})
create table if not exists public.incidents (
  id                  uuid primary key default gen_random_uuid(),
  organization_id     text not null references public.organizations (id),
  organization_name   text,
  flight_code         text not null,
  flight_key          text not null references public.flights (flight_key),
  title               text not null check (length(trim(title)) > 0),
  category            text not null default 'Outro',
  priority            text not null default 'normal' check (priority in ('normal', 'high', 'critical')),
  status              text not null default 'open',
  summary_internal    text not null default '',
  created_by          uuid references auth.users (id),
  assigned_area_ids   text[] not null check (cardinality(assigned_area_ids) > 0),
  assigned_area_names jsonb not null default '{}'::jsonb,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now()
);

-- Cartão da ocorrência no quadro da área (antes: .../areas/{areaId}/boards/{incidentId})
create table if not exists public.boards (
  org_id      text not null,
  area_id     text not null,
  incident_id uuid not null references public.incidents (id) on delete cascade,
  flight_code text,
  title       text,
  category    text,
  priority    text,
  created_at  timestamptz not null default now(),
  primary key (org_id, area_id, incident_id),
  foreign key (org_id, area_id) references public.areas (org_id, id)
);

-- Histórico interno compartilhado (antes: incidents/{id}/internalUpdates)
create table if not exists public.internal_updates (
  id          uuid primary key default gen_random_uuid(),
  incident_id uuid not null references public.incidents (id) on delete cascade,
  area_id     text not null,
  area_name   text,
  role        text,
  author_id   uuid references auth.users (id),
  content     text not null check (length(trim(content)) > 0),
  created_at  timestamptz not null default now()
);

-- Estado de cada área na ocorrência (antes: incidents/{id}/areaStatus/{areaId})
create table if not exists public.area_status (
  incident_id uuid not null references public.incidents (id) on delete cascade,
  area_id     text not null,
  state       text not null default 'waiting' check (state in ('waiting', 'working', 'done')),
  updated_by  uuid references auth.users (id),
  updated_at  timestamptz not null default now(),
  primary key (incident_id, area_id)
);

-- Comunicados públicos ao passageiro (antes: flights/{flightKey}/publicUpdates)
create table if not exists public.public_updates (
  id              uuid primary key default gen_random_uuid(),
  flight_key      text not null references public.flights (flight_key),
  flight_code     text not null,
  incident_id     uuid not null references public.incidents (id) on delete cascade,
  organization_id text not null,
  area_id         text not null,
  status          text not null check (length(trim(status)) > 0),
  message         text not null check (length(trim(message)) > 0),
  published_by    uuid references auth.users (id),
  published_at    timestamptz not null default now(),
  next_update_at  timestamptz
);

create index if not exists idx_boards_area            on public.boards (org_id, area_id);
create index if not exists idx_internal_updates_inc   on public.internal_updates (incident_id, created_at desc);
create index if not exists idx_public_updates_flight  on public.public_updates (flight_key, published_at desc);
create index if not exists idx_customer_flights_user  on public.customer_flights (user_id);
create index if not exists idx_memberships_user       on public.memberships (user_id);

-- ---------------------------------------------------------------------
-- PERFIL AUTOMÁTICO NO CADASTRO
-- Todo cadastro pelo site vira sempre "customer". Funcionários são
-- promovidos somente por SQL/painel (veja 03_dados_iniciais.sql).
-- ---------------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, full_name, email, account_type)
  values (
    new.id,
    coalesce(nullif(trim(new.raw_user_meta_data ->> 'full_name'), ''), split_part(coalesce(new.email, ''), '@', 1)),
    coalesce(new.email, ''),
    'customer'
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------
-- FUNÇÕES AUXILIARES DE PERMISSÃO (equivalentes às functions do Firestore)
-- ---------------------------------------------------------------------
create or replace function public.is_customer()
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.profiles p
    where p.id = auth.uid() and p.account_type = 'customer'
  );
$$;

create or replace function public.has_membership(p_org text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = auth.uid() and m.org_id = p_org and m.active
  );
$$;

create or replace function public.can_access_area(p_org text, p_area text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = auth.uid() and m.org_id = p_org and m.active
      and (p_area = any (m.area_ids) or m.can_view_all)
  );
$$;

create or replace function public.can_manage_incidents(p_org text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = auth.uid() and m.org_id = p_org and m.active and m.can_manage_incidents
  );
$$;

create or replace function public.can_read_incident_row(p_org text, p_assigned text[])
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.memberships m
    where m.user_id = auth.uid() and m.org_id = p_org and m.active
      and (m.can_view_all or m.area_ids && p_assigned)
  );
$$;

create or replace function public.can_read_incident(p_incident uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((
    select public.can_read_incident_row(i.organization_id, i.assigned_area_ids)
    from public.incidents i where i.id = p_incident
  ), false);
$$;

-- Papel da pessoa numa área (mesma regra usada pela interface)
create or replace function public.area_role(p_org text, p_area text)
returns text language sql stable security definer set search_path = ''
as $$
  select coalesce(m.roles ->> p_area, case when m.can_manage_incidents then 'cco' else 'employee' end)
  from public.memberships m
  where m.user_id = auth.uid() and m.org_id = p_org and m.active
    and (p_area = any (m.area_ids) or m.can_view_all);
$$;

create or replace function public.follows_flight(p_flight_key text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select exists (
    select 1 from public.customer_flights cf
    where cf.user_id = auth.uid() and cf.flight_key = p_flight_key
  );
$$;

-- ---------------------------------------------------------------------
-- RPC: criar ocorrência (substitui o writeBatch de incidents + boards)
-- ---------------------------------------------------------------------
create or replace function public.create_incident(
  p_org_id      text,
  p_flight_code text,
  p_title       text,
  p_category    text,
  p_priority    text,
  p_summary     text,
  p_area_ids    text[]
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid        uuid := auth.uid();
  v_member     public.memberships%rowtype;
  v_org_name   text;
  v_key        text := upper(regexp_replace(coalesce(p_flight_code, ''), '[^A-Za-z0-9]', '', 'g'));
  v_flight     public.flights%rowtype;
  v_areas      text[];
  v_names      jsonb;
  v_valid      int;
  v_id         uuid;
begin
  if v_uid is null then raise exception 'Entre na sua conta para continuar.'; end if;

  select * into v_member from public.memberships
   where user_id = v_uid and org_id = p_org_id and active;
  if not found or not v_member.can_manage_incidents then
    raise exception 'Sua conta não tem permissão para abrir ocorrências nesta organização.';
  end if;

  select name into v_org_name from public.organizations where id = p_org_id;
  if v_org_name is null then raise exception 'Organização não encontrada.'; end if;

  if v_key !~ '^[A-Z0-9]{4,12}$' then raise exception 'Digite um código de voo válido.'; end if;
  select * into v_flight from public.flights where flight_key = v_key;
  if not found then raise exception 'Voo % não encontrado no cadastro de voos.', upper(trim(p_flight_code)); end if;

  if coalesce(trim(p_title), '') = '' then raise exception 'Informe o título da ocorrência.'; end if;
  if coalesce(p_priority, '') not in ('normal', 'high', 'critical') then raise exception 'Prioridade inválida.'; end if;

  select array_agg(distinct a) into v_areas from unnest(coalesce(p_area_ids, '{}')) a where a is not null and a <> '';
  if v_areas is null or cardinality(v_areas) = 0 then raise exception 'Selecione ao menos uma área.'; end if;

  select count(*), jsonb_object_agg(ar.id, ar.name)
    into v_valid, v_names
    from public.areas ar
   where ar.org_id = p_org_id and ar.active and ar.id = any (v_areas);
  if v_valid <> cardinality(v_areas) then raise exception 'Há áreas inválidas ou inativas na seleção.'; end if;

  if not v_member.can_view_all and not (v_member.area_ids && v_areas) then
    raise exception 'A ocorrência precisa incluir ao menos uma área do seu credenciamento.';
  end if;

  insert into public.incidents (organization_id, organization_name, flight_code, flight_key, title, category, priority,
                                status, summary_internal, created_by, assigned_area_ids, assigned_area_names)
  values (p_org_id, v_org_name, v_flight.flight_code, v_key, trim(p_title), coalesce(nullif(trim(p_category), ''), 'Outro'),
          p_priority, 'open', coalesce(trim(p_summary), ''), v_uid, v_areas, v_names)
  returning id into v_id;

  insert into public.boards (org_id, area_id, incident_id, flight_code, title, category, priority)
  select p_org_id, a, v_id, v_flight.flight_code, trim(p_title), coalesce(nullif(trim(p_category), ''), 'Outro'), p_priority
    from unnest(v_areas) a;

  return v_id;
end;
$$;

-- ---------------------------------------------------------------------
-- RPC: registrar atualização da área e/ou publicar ao passageiro
-- (substitui o writeBatch de internalUpdates + areaStatus + publicUpdates)
-- ---------------------------------------------------------------------
create or replace function public.register_incident_update(
  p_incident_id    uuid,
  p_area_id        text,
  p_content        text default null,
  p_area_state     text default null,
  p_public_status  text default null,
  p_public_message text default null,
  p_next_update_at timestamptz default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid       uuid := auth.uid();
  v_incident  public.incidents%rowtype;
  v_role      text;
  v_area_name text;
  v_content   text := nullif(trim(coalesce(p_content, '')), '');
  v_message   text := nullif(trim(coalesce(p_public_message, '')), '');
  v_status    text := nullif(trim(coalesce(p_public_status, '')), '');
begin
  if v_uid is null then raise exception 'Entre na sua conta para continuar.'; end if;

  select * into v_incident from public.incidents where id = p_incident_id;
  if not found then raise exception 'Ocorrência não encontrada.'; end if;

  if not public.can_read_incident_row(v_incident.organization_id, v_incident.assigned_area_ids)
     or not public.can_access_area(v_incident.organization_id, p_area_id) then
    raise exception 'Sua conta não tem permissão para esta ação. Confira o credenciamento da área.';
  end if;
  if not (p_area_id = any (v_incident.assigned_area_ids)) then
    raise exception 'Esta área não está vinculada à ocorrência.';
  end if;

  v_role := public.area_role(v_incident.organization_id, p_area_id);
  select name into v_area_name from public.areas where org_id = v_incident.organization_id and id = p_area_id;

  if v_content is not null then
    insert into public.internal_updates (incident_id, area_id, area_name, role, author_id, content)
    values (p_incident_id, p_area_id, coalesce(v_area_name, p_area_id), v_role, v_uid, v_content);
  end if;

  if p_area_state is not null then
    if p_area_state not in ('waiting', 'working', 'done') then raise exception 'Estado da área inválido.'; end if;
    insert into public.area_status (incident_id, area_id, state, updated_by, updated_at)
    values (p_incident_id, p_area_id, p_area_state, v_uid, now())
    on conflict (incident_id, area_id)
    do update set state = excluded.state, updated_by = excluded.updated_by, updated_at = excluded.updated_at;
  end if;

  if v_message is not null then
    if v_status is null then raise exception 'Informe o status público para publicar a mensagem.'; end if;
    if coalesce(v_role, '') not in ('cco', 'admin', 'customer_service', 'commercial') then
      raise exception 'Seu papel nesta área não permite publicar mensagens para passageiros.';
    end if;
    insert into public.public_updates (flight_key, flight_code, incident_id, organization_id, area_id,
                                       status, message, published_by, next_update_at)
    values (v_incident.flight_key, v_incident.flight_code, p_incident_id, v_incident.organization_id, p_area_id,
            v_status, v_message, v_uid, p_next_update_at);
  end if;

  update public.incidents set updated_at = now() where id = p_incident_id;
end;
$$;
