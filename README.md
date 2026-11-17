# Megawatt Gestão

Aplicação estática para GitHub Pages, com autenticação e dados compartilhados pelo Supabase.

## Estrutura

- `index.html`: interface do sistema.
- `supabase-config.js`: URL e chave pública (publishable/anon) do projeto Supabase.
- `supabase/schema.sql`: tabelas, permissões e políticas RLS.
- `supabase/functions/admin-manage-user/index.ts`: função administrativa para criar, editar e excluir contas.
- `supabase/config.toml`: configuração de verificação JWT da Edge Function.

## 1. Configurar o Supabase

1. Abra o projeto no Supabase.
2. Entre em **SQL Editor** e execute todo o conteúdo de `supabase/schema.sql`.
3. Em **Project Settings / API** (ou **Data API / API Keys**, conforme a interface), copie a **Project URL** e a chave **publishable**. Em projetos antigos, a chave `anon` também funciona.
4. Cole esses dois valores em `supabase-config.js`:
   - `MEGAWATT_SUPABASE_URL`: Project URL.
   - `MEGAWATT_SUPABASE_ANON_KEY`: publishable key ou anon key.
5. Não coloque no arquivo a chave `secret` nem `service_role`.

## 2. Criar o primeiro administrador

O primeiro administrador é criado manualmente uma única vez, pois ainda não existe uma conta administradora para autorizar o cadastro pela aplicação.

1. No Supabase, abra **Authentication → Users → Add user**.
2. Cadastre o e-mail e uma senha forte do administrador. Confirme/crie o usuário.
3. Copie o UUID desse usuário na lista de Authentication → Users.
4. No SQL Editor, execute o comando abaixo substituindo os três valores de exemplo:

```sql
insert into public.profiles (id, email, username, display_name, role, work)
values (
  'COLE_AQUI_O_UUID_DO_AUTH_USER',
  'admin@seudominio.com',
  'admin',
  'Administrador',
  'admin',
  '{"days":[1,2,3,4,5],"start":"08:00","end":"18:00"}'::jsonb
);
```

Use exatamente o mesmo e-mail usado ao criar o usuário em Authentication. O perfil inicial deve ter um `username` único (por exemplo, `admin`). Depois de publicar a Edge Function `login-by-username`, o acesso ao Megawatt será feito com esse nome de usuário e a senha criada. O cadastro dos demais funcionários será feito pela tela **Usuários**.

## 3. Publicar a Edge Function administrativa

A tela de usuários usa uma Edge Function para criar contas no Supabase Auth. A chave privilegiada fica somente no ambiente do Supabase, nunca no GitHub nem no navegador.

Instale o Supabase CLI e, no terminal, dentro desta pasta do projeto:

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase functions deploy admin-manage-user
supabase functions deploy login-by-username
```

O `project-ref` aparece na URL do projeto ou nas configurações do projeto. A função usa as variáveis de ambiente fornecidas pelo Supabase (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEYS` e `SUPABASE_SECRET_KEYS`, com compatibilidade para as chaves legadas). Não é necessário copiar uma chave secreta para o repositório.

O código lê as chaves de ambiente que o Supabase injeta nas Edge Functions. A chave secreta não precisa ser adicionada ao repositório nem ao JavaScript do site.

## 4. Configurar Authentication

- Em **Authentication → Providers**, mantenha Email habilitado.
- Desative o cadastro público/sign-ups, pois as contas serão criadas pelo administrador.
- Em **Authentication → URL Configuration**, configure a URL do GitHub Pages como Site URL e inclua a URL publicada em Redirect URLs.
- O administrador cria as contas por meio da Edge Function; ela confirma o e-mail na criação para permitir o acesso imediato.

## 5. Publicar pelo GitHub Pages

1. Crie um repositório no GitHub. Para uso de empresa, prefira repositório **privado** se seu plano permitir GitHub Pages para repositórios privados; de todo modo, considere que o código entregue ao navegador sempre será público.
2. Envie a pasta do projeto para a raiz do repositório. `index.html` e `supabase-config.js` precisam ficar na raiz.
3. No GitHub, abra **Settings → Pages**.
4. Em **Build and deployment**, selecione **Deploy from a branch**, branch `main` e pasta `/ (root)`.
5. Salve e aguarde a publicação. O GitHub exibirá o endereço do site.
6. Adicione esse endereço em Supabase **Authentication → URL Configuration**.

## Perfis e permissões

- **Administrador:** gerencia funcionários e permissões; cria, edita e exclui dados.
- **Editor:** cria e altera tarefas, contatos, links e anotações.
- **Leitor:** consulta os dados, sem permissão para alterá-los.

As permissões no banco são aplicadas por Row Level Security (RLS), não apenas escondendo botões da interface.

## Segurança — importante

- A chave publishable/anon pode estar no frontend quando RLS está corretamente configurado.
- Nunca publique `service_role`, `secret key`, senha de administrador, token de acesso ou arquivo `.env`.
- Nunca habilite acesso anônimo às tabelas internas.
- Antes de usar com dados reais, teste cada perfil em uma sessão separada: administrador, editor e leitor.
- Contatos, links, anotações e preferências globais continuam no registro compartilhado; as tarefas foram separadas em linhas individuais na tabela `workspace_tasks` para reduzir conflitos de atualização simultânea.

## Atualizações Megawatt — novembro/2026

Antes de publicar a versão atualizada, execute no **SQL Editor** do Supabase o arquivo `supabase/migrations/20261117_megawatt_updates.sql`. Essa migração:

- cria a tabela de histórico de pesagens, com acesso autenticado e exclusão restrita a administradores;
- configura a limpeza de pesagens com mais de 24 horas (pg_cron quando disponível; a aplicação também limpa ao abrir/consultar o histórico, ao lançar pesagens e a cada cinco minutos enquanto houver uma sessão ativa);
- cria uma tabela própria para tarefas, evitando que a criação de uma tarefa por um funcionário substitua a tarefa criada simultaneamente por outro;
- habilita as tabelas necessárias no Supabase Realtime.

### Login por nome de usuário

A tela de login agora recebe nome de usuário e senha. Para manter o e-mail de autenticação protegido, o projeto usa a Edge Function `login-by-username` para localizar a conta e autenticar. Publique-a com:

```bash
supabase functions deploy login-by-username
```

A função usa a chave privilegiada somente no ambiente do Supabase. A seção `[functions.login-by-username] verify_jwt = false` já está no `supabase/config.toml`, pois o usuário ainda não possui sessão no momento do login. Não remova a validação de sessão da função administrativa `admin-manage-user`.

### Conversor e tabela de referência

A página **Conversor de fios** incorpora o conversor original em `https://foygi.github.io/wireConverter/` e também disponibiliza o cálculo dentro do Megawatt. A aba separada **Tabela de fios** é visível e editável somente por administradores (com a restrição aplicada também no banco). O conversor nativo usa essa tabela e as colunas:

- `type`: tipo de produto;
- `gauge`: bitola/produto;
- `referenceWeight`: peso de referência em kg;
- `referenceMeters`: metragem de referência em m.

Os dados da tabela original não foram incluídos no ZIP recebido e não são expostos pelo conteúdo público legível da página externa. Portanto, o administrador deverá preencher a tabela interna com os dados oficiais da planilha. A tabela administrada alimenta o cálculo nativo do Megawatt; a página externa continua incorporada como acesso direto ao conversor original e não sincroniza sua própria planilha com o Megawatt. Os dados oficiais precisam ser cadastrados na aba **Tabela de fios** para que o cálculo nativo fique pronto. A fórmula de referência segue a proporção quantidade de referência ÷ peso de referência × peso informado, descrita no conversor original.

### Histórico de pesagens

Cada lançamento guarda data/hora, bitola, peso, metragem e usuário autenticado. O histórico fica visível aos usuários autenticados e a exclusão manual integral é restrita a administradores. Os registros expiram após 24 horas; o agendamento exato depende de `pg_cron` estar habilitado no projeto Supabase.

### Painel e tarefas

Cada perfil pode organizar seu painel arrastando blocos, alterando largura/altura e escolhendo quais aparecem. Anotações novas são fixadas no painel por padrão, mas podem ser desmarcadas no formulário. Tarefas são armazenadas separadamente e recebem eventos Realtime; o início e a conclusão registram responsável e horário.
