-- =====================================================================
-- Azul em Sintonia — 03_dados_iniciais.sql
-- Rode DEPOIS do 02_regras_rls.sql. Pode rodar de novo: atualiza os
-- horários dos voos para o dia de hoje e não duplica nada.
--
-- Cria: catálogo de voos, organização + áreas, contas de demonstração
-- (funcionários e um cliente) e uma ocorrência de exemplo.
--
-- Contas criadas (senha de todas: Azul@2026 — troque depois em
-- Authentication → Users se for apresentar publicamente):
--   cco@exemplo.com          CCO (vê todas as áreas, abre ocorrências)
--   manutencao@exemplo.com   Manutenção
--   handling@exemplo.com     Handling
--   atendimento@exemplo.com  Atendimento (publica ao passageiro)
--   comercial@exemplo.com    Comercial   (publica ao passageiro)
--   cliente@exemplo.com      Cliente (já acompanha AD 4281 e AD 4302)
-- =====================================================================

-- 1) CATÁLOGO DE VOOS -------------------------------------------------
-- Horários gerados para "hoje" no fuso de São Paulo.
with base as (
  select date_trunc('day', now() at time zone 'America/Sao_Paulo') as dia
),
v (flight_code, origin, origin_city, destination, destination_city, partida, duracao, aircraft) as (
  values
    ('AD 4050', 'VCP', 'Campinas',        'SDU', 'Rio de Janeiro',     time '06:00', interval '1 hour',             'Embraer E195-E2'),
    ('AD 4062', 'SDU', 'Rio de Janeiro',  'VCP', 'Campinas',           time '07:30', interval '1 hour',             'Embraer E195-E2'),
    ('AD 4100', 'VCP', 'Campinas',        'CNF', 'Belo Horizonte',     time '07:15', interval '1 hour 15 minutes',  'Embraer E195'),
    ('AD 2711', 'CGH', 'São Paulo',       'SDU', 'Rio de Janeiro',     time '08:00', interval '1 hour',             'Embraer E195-E2'),
    ('AD 4302', 'VCP', 'Campinas',        'REC', 'Recife',             time '08:40', interval '3 hours 15 minutes', 'Airbus A320neo'),
    ('AD 4281', 'GRU', 'São Paulo',       'REC', 'Recife',             time '09:10', interval '3 hours 20 minutes', 'Airbus A320neo'),
    ('AD 4170', 'REC', 'Recife',          'FEN', 'Fernando de Noronha',time '10:00', interval '1 hour 10 minutes',  'ATR 72-600'),
    ('AD 4416', 'VCP', 'Campinas',        'POA', 'Porto Alegre',       time '10:20', interval '1 hour 45 minutes',  'Airbus A320neo'),
    ('AD 4520', 'VCP', 'Campinas',        'BSB', 'Brasília',           time '11:05', interval '1 hour 40 minutes',  'Embraer E195-E2'),
    ('AD 4632', 'CNF', 'Belo Horizonte',  'SSA', 'Salvador',           time '12:30', interval '1 hour 50 minutes',  'Embraer E195-E2'),
    ('AD 4700', 'REC', 'Recife',          'FOR', 'Fortaleza',          time '13:15', interval '1 hour 10 minutes',  'Embraer E195'),
    ('AD 4815', 'BSB', 'Brasília',        'BEL', 'Belém',              time '14:00', interval '2 hours 45 minutes', 'Airbus A320neo'),
    ('AD 4920', 'VCP', 'Campinas',        'FLN', 'Florianópolis',      time '15:30', interval '1 hour 20 minutes',  'Embraer E195'),
    ('AD 5011', 'SDU', 'Rio de Janeiro',  'CNF', 'Belo Horizonte',     time '16:10', interval '1 hour 5 minutes',   'ATR 72-600'),
    ('AD 5123', 'VCP', 'Campinas',        'CWB', 'Curitiba',           time '17:00', interval '1 hour 5 minutes',   'ATR 72-600'),
    ('AD 2470', 'VCP', 'Campinas',        'MAO', 'Manaus',             time '18:20', interval '4 hours',            'Airbus A320neo'),
    ('AD 4381', 'GRU', 'São Paulo',       'CNF', 'Belo Horizonte',     time '19:40', interval '1 hour 10 minutes',  'Embraer E195-E2'),
    ('AD 4900', 'POA', 'Porto Alegre',    'VCP', 'Campinas',           time '20:15', interval '1 hour 45 minutes',  'Airbus A320neo'),
    ('AD 8750', 'VCP', 'Campinas',        'ORY', 'Paris',              time '21:30', interval '11 hours',           'Airbus A330neo'),
    ('AD 8700', 'VCP', 'Campinas',        'FLL', 'Fort Lauderdale',    time '22:10', interval '9 hours 30 minutes', 'Airbus A330neo'),
    ('AD 8710', 'VCP', 'Campinas',        'MCO', 'Orlando',            time '23:00', interval '9 hours',            'Airbus A330neo')
)
insert into public.flights (flight_key, flight_code, origin, origin_city, destination, destination_city,
                            scheduled_departure, scheduled_arrival, aircraft)
select upper(regexp_replace(v.flight_code, '[^A-Za-z0-9]', '', 'g')),
       v.flight_code, v.origin, v.origin_city, v.destination, v.destination_city,
       (base.dia + v.partida) at time zone 'America/Sao_Paulo',
       (base.dia + v.partida + v.duracao) at time zone 'America/Sao_Paulo',
       v.aircraft
from v cross join base
on conflict (flight_key) do update
  set flight_code = excluded.flight_code,
      origin = excluded.origin, origin_city = excluded.origin_city,
      destination = excluded.destination, destination_city = excluded.destination_city,
      scheduled_departure = excluded.scheduled_departure,
      scheduled_arrival = excluded.scheduled_arrival,
      aircraft = excluded.aircraft;

-- 2) ORGANIZAÇÃO E ÁREAS ----------------------------------------------
insert into public.organizations (id, name)
values ('azul-operacao', 'Operação de demonstração')
on conflict (id) do update set name = excluded.name;

insert into public.areas (org_id, id, name, active) values
  ('azul-operacao', 'cco',         'CCO',         true),
  ('azul-operacao', 'manutencao',  'Manutenção',  true),
  ('azul-operacao', 'handling',    'Handling',    true),
  ('azul-operacao', 'atendimento', 'Atendimento', true),
  ('azul-operacao', 'comercial',   'Comercial',   true)
on conflict (org_id, id) do update set name = excluded.name, active = excluded.active;

-- 3) CONTAS DE DEMONSTRAÇÃO (Authentication) --------------------------
do $$
declare
  u record;
begin
  for u in
    select * from (values
      ('11111111-1111-4111-8111-111111111111'::uuid, 'cco@exemplo.com',         'Carla Souza (CCO)'),
      ('22222222-2222-4222-8222-222222222222'::uuid, 'manutencao@exemplo.com',  'Marcos Lima (Manutenção)'),
      ('33333333-3333-4333-8333-333333333333'::uuid, 'handling@exemplo.com',    'Henrique Alves (Handling)'),
      ('44444444-4444-4444-8444-444444444444'::uuid, 'atendimento@exemplo.com', 'Ana Ribeiro (Atendimento)'),
      ('55555555-5555-4555-8555-555555555555'::uuid, 'comercial@exemplo.com',   'Paulo Mendes (Comercial)'),
      ('66666666-6666-4666-8666-666666666666'::uuid, 'cliente@exemplo.com',     'Júlia Passageira')
    ) as t (id, email, full_name)
  loop
    if not exists (select 1 from auth.users where id = u.id or email = u.email) then
      insert into auth.users (
        instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
        raw_app_meta_data, raw_user_meta_data, created_at, updated_at,
        confirmation_token, email_change, email_change_token_new, recovery_token
      ) values (
        '00000000-0000-0000-0000-000000000000', u.id, 'authenticated', 'authenticated', u.email,
        extensions.crypt('Azul@2026', extensions.gen_salt('bf')), now(),
        '{"provider":"email","providers":["email"]}'::jsonb,
        jsonb_build_object('full_name', u.full_name), now(), now(),
        '', '', '', ''
      );
      insert into auth.identities (id, user_id, provider_id, identity_data, provider, last_sign_in_at, created_at, updated_at)
      values (
        gen_random_uuid(), u.id, u.id::text,
        jsonb_build_object('sub', u.id::text, 'email', u.email, 'email_verified', true),
        'email', now(), now(), now()
      );
    end if;
  end loop;
end $$;

-- Perfis (o gatilho já cria como cliente; aqui promovemos os funcionários)
insert into public.profiles (id, full_name, email, account_type)
select u.id, x.full_name, u.email, x.account_type
from auth.users u
join (values
  ('cco@exemplo.com',         'Carla Souza',     'employee'),
  ('manutencao@exemplo.com',  'Marcos Lima',     'employee'),
  ('handling@exemplo.com',    'Henrique Alves',  'employee'),
  ('atendimento@exemplo.com', 'Ana Ribeiro',     'employee'),
  ('comercial@exemplo.com',   'Paulo Mendes',    'employee'),
  ('cliente@exemplo.com',     'Júlia Passageira','customer')
) as x (email, full_name, account_type) on x.email = u.email
on conflict (id) do update
  set full_name = excluded.full_name, email = excluded.email, account_type = excluded.account_type;

-- 4) CREDENCIAMENTO (vínculos com organização, áreas e papéis) --------
insert into public.memberships (user_id, org_id, active, organization_name, area_ids, area_names, roles, can_view_all, can_manage_incidents)
select u.id, 'azul-operacao', true, 'Operação de demonstração', x.area_ids, x.area_names, x.roles, x.can_view_all, x.can_manage
from auth.users u
join (values
  ('cco@exemplo.com',
     array['cco','manutencao','handling','atendimento','comercial'],
     '{"cco":"CCO","manutencao":"Manutenção","handling":"Handling","atendimento":"Atendimento","comercial":"Comercial"}'::jsonb,
     '{"cco":"cco","manutencao":"cco","handling":"cco","atendimento":"cco","comercial":"cco"}'::jsonb,
     true, true),
  ('manutencao@exemplo.com',  array['manutencao'],  '{"manutencao":"Manutenção"}'::jsonb,   '{"manutencao":"maintenance"}'::jsonb,       false, false),
  ('handling@exemplo.com',    array['handling'],    '{"handling":"Handling"}'::jsonb,       '{"handling":"handling"}'::jsonb,            false, false),
  ('atendimento@exemplo.com', array['atendimento'], '{"atendimento":"Atendimento"}'::jsonb, '{"atendimento":"customer_service"}'::jsonb, false, false),
  ('comercial@exemplo.com',   array['comercial'],   '{"comercial":"Comercial"}'::jsonb,     '{"comercial":"commercial"}'::jsonb,         false, false)
) as x (email, area_ids, area_names, roles, can_view_all, can_manage) on x.email = u.email
on conflict (user_id, org_id) do update
  set active = excluded.active, organization_name = excluded.organization_name, area_ids = excluded.area_ids,
      area_names = excluded.area_names, roles = excluded.roles,
      can_view_all = excluded.can_view_all, can_manage_incidents = excluded.can_manage_incidents;

-- 5) CLIENTE DE DEMONSTRAÇÃO ACOMPANHANDO VOOS ------------------------
insert into public.customer_flights (user_id, flight_key, flight_code)
select u.id, f.flight_key, f.flight_code
from auth.users u
join public.flights f on f.flight_key in ('AD4281', 'AD4302')
where u.email = 'cliente@exemplo.com'
on conflict (user_id, flight_key) do nothing;

-- 6) OCORRÊNCIA DE EXEMPLO (AD 4281) ----------------------------------
do $$
declare
  v_cco   uuid := (select id from auth.users where email = 'cco@exemplo.com');
  v_man   uuid := (select id from auth.users where email = 'manutencao@exemplo.com');
  v_atd   uuid := (select id from auth.users where email = 'atendimento@exemplo.com');
  v_inc   uuid := 'aaaaaaaa-0000-4000-8000-000000004281';
begin
  if exists (select 1 from public.incidents where id = v_inc) then return; end if;

  insert into public.incidents (id, organization_id, organization_name, flight_code, flight_key, title, category, priority,
                                status, summary_internal, created_by, assigned_area_ids, assigned_area_names, created_at, updated_at)
  values (v_inc, 'azul-operacao', 'Operação de demonstração', 'AD 4281', 'AD4281',
          'Inspeção técnica antes da partida', 'Manutenção', 'high', 'open',
          'Alerta no sistema hidráulico identificado no pré-voo. Aeronave em inspeção; avaliar troca de aeronave se passar de 40 min.',
          v_cco, array['cco','manutencao','atendimento'],
          '{"cco":"CCO","manutencao":"Manutenção","atendimento":"Atendimento"}'::jsonb,
          now() - interval '35 minutes', now() - interval '5 minutes');

  insert into public.boards (org_id, area_id, incident_id, flight_code, title, category, priority, created_at)
  select 'azul-operacao', a, v_inc, 'AD 4281', 'Inspeção técnica antes da partida', 'Manutenção', 'high', now() - interval '35 minutes'
  from unnest(array['cco','manutencao','atendimento']) a;

  insert into public.internal_updates (incident_id, area_id, area_name, role, author_id, content, created_at) values
    (v_inc, 'cco',         'CCO',         'cco',              v_cco, 'Ocorrência aberta. Manutenção acionada e atendimento avisado no portão 12.', now() - interval '35 minutes'),
    (v_inc, 'manutencao',  'Manutenção',  'maintenance',      v_man, 'Sensor hidráulico em teste. Previsão de diagnóstico em 20 minutos.',         now() - interval '20 minutes'),
    (v_inc, 'atendimento', 'Atendimento', 'customer_service', v_atd, 'Passageiros informados no portão. Água distribuída.',                         now() - interval '8 minutes');

  insert into public.area_status (incident_id, area_id, state, updated_by, updated_at) values
    (v_inc, 'cco',         'working', v_cco, now() - interval '35 minutes'),
    (v_inc, 'manutencao',  'working', v_man, now() - interval '20 minutes'),
    (v_inc, 'atendimento', 'working', v_atd, now() - interval '8 minutes');

  insert into public.public_updates (flight_key, flight_code, incident_id, organization_id, area_id, status, message,
                                     published_by, published_at, next_update_at)
  values ('AD4281', 'AD 4281', v_inc, 'azul-operacao', 'atendimento', 'Inspeção técnica em andamento',
          'Nossa equipe está trabalhando para liberar a aeronave com segurança. Permaneça próximo ao portão de embarque.',
          v_atd, now() - interval '5 minutes', now() + interval '25 minutes');
end $$;
