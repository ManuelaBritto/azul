# Estrutura do produto — Azul em Sintonia

## Objetivo

Centralizar uma ocorrência e comunicar atualizações coerentes às equipes envolvidas e ao passageiro. A mesma ocorrência tem um histórico compartilhado; cada área mantém seu próprio status e o passageiro recebe apenas a mensagem pública.

## Áreas do site

### Pública

- Página inicial com apresentação do serviço, como funciona e chamadas para cliente e funcionário.
- Cadastro e login de cliente.
- Entrada operacional separada; não há cadastro público de funcionário.

### Cliente

- Cadastrar códigos de voo para acompanhar.
- Consultar mensagens públicas e a hora da próxima atualização.
- Sem acesso a diagnóstico interno, notas das equipes, nem informações pessoais dos funcionários.

### Operacional

- Organizações e áreas aparecem conforme o credenciamento da conta.
- Cada quadro mostra ocorrências atribuídas à área.
- CCO/admin abre ocorrência e escolhe áreas responsáveis.
- Áreas registram atualizações e estado de trabalho; as demais áreas vinculadas acompanham o mesmo histórico.
- Papéis autorizados publicam mensagem separada e simplificada para o passageiro.

## Fluxo da ocorrência

1. CCO cria ocorrência com voo, categoria, prioridade e resumo.
2. CCO seleciona as áreas envolvidas; um cartão da ocorrência aparece em cada quadro escolhido.
3. Cada área atualiza o próprio estado e registra o que mudou na linha do tempo interna compartilhada.
4. Atendimento, Comercial, CCO ou administrador autorizado redige a mensagem pública.
5. Passageiros que acompanham aquele código recebem apenas os comunicados publicados.

## Modelo do Supabase (Postgres)

- `profiles`: cliente ou funcionário (criado automaticamente no cadastro, sempre como cliente).
- `memberships`: organizações, áreas e papéis autorizados da pessoa funcionária.
- `organizations` e `areas`: organizações e equipes.
- `boards`: cartão visível no quadro da área.
- `incidents`: contexto central e IDs das áreas participantes.
- `internal_updates`: histórico operacional compartilhado.
- `area_status`: estado de trabalho de cada área.
- `flights`: catálogo de voos (código, origem, destino, horários, aeronave).
- `customer_flights`: códigos acompanhados pela conta de cliente (somente voos do catálogo).
- `public_updates`: comunicados que podem aparecer ao passageiro.

## Permissões

- O cadastro público só cria perfil de cliente (gatilho `handle_new_user` no banco).
- Funcionários entram com contas criadas por administrador e com vínculos provisionados via SQL.
- Regras RLS do Postgres validam cada leitura; escritas operacionais passam pelas funções `create_incident` e `register_incident_update`, que conferem organização, área e papel.
- Mensagens públicas ficam separadas das notas internas; o passageiro nunca lê `incidents`, `internal_updates` ou `area_status`.
- Nenhuma senha operacional compartilhada fica embutida no JavaScript; o site usa apenas a chave pública (anon).

## Limite de integração

A base suporta contas e dados inseridos pelos usuários autorizados após configuração do Supabase. Os voos do catálogo são de demonstração e não se conectam a sistemas da Azul. Para usar dados operacionais reais, é necessária autorização formal e integração oficial, além de revisão de segurança antes de qualquer uso fora do projeto acadêmico.
