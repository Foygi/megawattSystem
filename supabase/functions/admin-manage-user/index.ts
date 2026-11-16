import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  });

const validRole = (role: unknown) => ['admin', 'editor', 'reader'].includes(String(role));

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);

  try {
    const authorization = req.headers.get('Authorization');
    if (!authorization?.startsWith('Bearer ')) return json({ error: 'Sessão não informada.' }, 401);

    const projectUrl = Deno.env.get('SUPABASE_URL')!;
    // As variáveis SUPABASE_SECRET_KEYS / SUPABASE_PUBLISHABLE_KEYS são o padrão atual.
    // O fallback mantém compatibilidade com projetos que ainda expõem as chaves legadas.
    const secretMapRaw = Deno.env.get('SUPABASE_SECRET_KEYS');
    const serviceKey = secretMapRaw
      ? JSON.parse(secretMapRaw).default
      : Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const publishableMapRaw = Deno.env.get('SUPABASE_PUBLISHABLE_KEYS');
    const publishableKey = publishableMapRaw
      ? JSON.parse(publishableMapRaw).default
      : Deno.env.get('SUPABASE_ANON_KEY');

    if (!projectUrl || !serviceKey || !publishableKey) {
      return json({ error: 'Configuração interna do Supabase incompleta.' }, 500);
    }

    const token = authorization.slice('Bearer '.length);
    const authClient = createClient(projectUrl, publishableKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: authData, error: authError } = await authClient.auth.getUser(token);
    if (authError || !authData.user) return json({ error: 'Sessão inválida ou expirada.' }, 401);

    const admin = createClient(projectUrl, serviceKey, {
      auth: { persistSession: false, autoRefreshToken: false },
    });
    const { data: actor, error: actorError } = await admin
      .from('profiles').select('id, role').eq('id', authData.user.id).single();
    if (actorError || actor?.role !== 'admin') return json({ error: 'Apenas administradores podem gerenciar usuários.' }, 403);

    const body = await req.json();
    const action = String(body.action || '');

    if (action === 'create') {
      const email = String(body.email || '').trim().toLowerCase();
      const username = String(body.username || '').trim().toLowerCase();
      const display_name = String(body.display_name || '').trim();
      const password = String(body.password || '');
      const role = String(body.role || 'editor');
      const work = body.work;
      if (!email || !/^[a-z0-9._-]{3,32}$/.test(username) || !display_name || password.length < 8 || !validRole(role)) {
        return json({ error: 'Informe nome, usuário, e-mail, perfil e senha com pelo menos 8 caracteres.' }, 400);
      }
      if (!work || !Array.isArray(work.days) || work.days.length === 0 || !work.start || !work.end || work.end <= work.start) {
        return json({ error: 'Expediente inválido.' }, 400);
      }
      const { data: created, error: createError } = await admin.auth.admin.createUser({
        email,
        password,
        email_confirm: true,
        user_metadata: { username, display_name },
      });
      if (createError || !created.user) return json({ error: createError?.message || 'Não foi possível criar a conta.' }, 400);

      const { error: profileError } = await admin.from('profiles').insert({
        id: created.user.id, email, username, display_name, role, work,
      });
      if (profileError) {
        await admin.auth.admin.deleteUser(created.user.id);
        return json({ error: profileError.message }, 400);
      }
      return json({ ok: true, id: created.user.id });
    }

    if (action === 'update') {
      const id = String(body.id || '');
      if (!id) return json({ error: 'Identificador do usuário ausente.' }, 400);
      if (id === actor.id && body.role && body.role !== 'admin') {
        return json({ error: 'Não é permitido remover seu próprio perfil de administrador.' }, 400);
      }
      const email = String(body.email || '').trim().toLowerCase();
      const username = String(body.username || '').trim().toLowerCase();
      const display_name = String(body.display_name || '').trim();
      const role = String(body.role || 'editor');
      const work = body.work;
      if (!email || !/^[a-z0-9._-]{3,32}$/.test(username) || !display_name || !validRole(role) || !work || !Array.isArray(work.days) || !work.days.length || !work.start || !work.end || work.end <= work.start) {
        return json({ error: 'Dados do funcionário ou expediente inválidos.' }, 400);
      }
      const { data: emailDuplicate } = await admin.from('profiles').select('id').eq('email', email).neq('id', id).limit(1);
      const { data: usernameDuplicate } = await admin.from('profiles').select('id').eq('username', username).neq('id', id).limit(1);
      if (emailDuplicate?.length || usernameDuplicate?.length) return json({ error: 'Este e-mail ou nome de usuário já está em uso.' }, 409);
      const authChanges: Record<string, unknown> = { email, email_confirm: true, user_metadata: { username, display_name } };
      if (body.password) {
        if (String(body.password).length < 8) return json({ error: 'A nova senha deve ter pelo menos 8 caracteres.' }, 400);
        authChanges.password = String(body.password);
      }
      const { error: authUpdateError } = await admin.auth.admin.updateUserById(id, authChanges);
      if (authUpdateError) return json({ error: authUpdateError.message }, 400);
      const { error: profileUpdateError } = await admin.from('profiles')
        .update({ email, username, display_name, role, work, updated_at: new Date().toISOString() })
        .eq('id', id);
      if (profileUpdateError) return json({ error: profileUpdateError.message }, 400);
      return json({ ok: true });
    }

    if (action === 'delete') {
      const id = String(body.id || '');
      if (!id) return json({ error: 'Identificador do usuário ausente.' }, 400);
      if (id === actor.id) return json({ error: 'Você não pode excluir sua própria conta administrativa.' }, 400);
      const { data: target } = await admin.from('profiles').select('id, role').eq('id', id).single();
      if (!target) return json({ error: 'Usuário não encontrado.' }, 404);
      if (target.role === 'admin') {
        const { count } = await admin.from('profiles').select('id', { count: 'exact', head: true }).eq('role', 'admin');
        if ((count || 0) <= 1) return json({ error: 'O sistema precisa manter pelo menos um administrador.' }, 400);
      }
      const { error: deleteError } = await admin.auth.admin.deleteUser(id);
      if (deleteError) return json({ error: deleteError.message }, 400);
      return json({ ok: true });
    }

    return json({ error: 'Ação desconhecida.' }, 400);
  } catch (error) {
    console.error('admin-manage-user:', error);
    return json({ error: 'Erro interno ao processar a solicitação.' }, 500);
  }
});
