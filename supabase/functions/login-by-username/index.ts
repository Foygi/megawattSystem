import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status, headers: { ...corsHeaders, 'Content-Type': 'application/json' },
});

// Login por usuário sem expor o e-mail associado no navegador.
Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders });
  if (req.method !== 'POST') return json({ error: 'Método não permitido.' }, 405);
  try {
    const { username, password } = await req.json();
    const user = String(username || '').trim().toLowerCase();
    const pass = String(password || '');
    if (!/^[a-z0-9._-]{3,32}$/.test(user) || !pass) return json({ error: 'Usuário ou senha inválidos.' }, 400);

    const projectUrl = Deno.env.get('SUPABASE_URL')!;
    const secretMapRaw = Deno.env.get('SUPABASE_SECRET_KEYS');
    const serviceKey = secretMapRaw ? JSON.parse(secretMapRaw).default : Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
    const publishableMapRaw = Deno.env.get('SUPABASE_PUBLISHABLE_KEYS');
    const publishableKey = publishableMapRaw ? JSON.parse(publishableMapRaw).default : Deno.env.get('SUPABASE_ANON_KEY');
    if (!projectUrl || !serviceKey || !publishableKey) return json({ error: 'Configuração interna do Supabase incompleta.' }, 500);

    const admin = createClient(projectUrl, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data: profile, error: profileError } = await admin.from('profiles').select('email').eq('username', user).maybeSingle();
    if (profileError || !profile?.email) return json({ error: 'Usuário ou senha inválidos.' }, 401);

    const auth = createClient(projectUrl, publishableKey, { auth: { persistSession: false, autoRefreshToken: false } });
    const { data, error } = await auth.auth.signInWithPassword({ email: profile.email, password: pass });
    if (error || !data.session) return json({ error: 'Usuário ou senha inválidos.' }, 401);
    return json({ access_token: data.session.access_token, refresh_token: data.session.refresh_token });
  } catch (error) {
    console.error('login-by-username:', error);
    return json({ error: 'Não foi possível autenticar neste momento.' }, 500);
  }
});
