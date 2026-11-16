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

Use exatamente o mesmo e-mail usado ao criar o usuário em Authentication. A partir daí, entre no Megawatt Gestão com esse e-mail e a senha criada. O cadastro dos demais funcionários será feito pela tela **Usuários**.

## 3. Publicar a Edge Function administrativa

A tela de usuários usa uma Edge Function para criar contas no Supabase Auth. A chave privilegiada fica somente no ambiente do Supabase, nunca no GitHub nem no navegador.

Instale o Supabase CLI e, no terminal, dentro desta pasta do projeto:

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase functions deploy admin-manage-user
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
- O estado operacional (tarefas, contatos, links e anotações) fica em um registro JSON compartilhado. Para uma equipe pequena é simples de manter; se houver muitos usuários editando simultaneamente, a próxima evolução recomendada é separar cada tipo de dado em tabelas próprias para reduzir conflitos de atualização.
