/**
 * 科普内容库 · 在线保存后端（Cloudflare Workers）
 * ---------------------------------------------------------------
 * 作用：浏览器改完稿 → 本服务 → GitHub API → 直接 commit 进仓库
 *      （一次请求可写多个文件，只产生一个 commit）
 *
 * 环境变量（在 Cloudflare 后台设置，绝不进仓库）：
 *   GH_TOKEN     GitHub 个人访问令牌（fine-grained，只对这一个仓库，Contents: Read and write）
 *   GH_OWNER     仓库所有者，如 lipulin222
 *   GH_REPO      仓库名，如 weight-management-kb
 *   GH_BRANCH    分支，如 main
 *   SAVE_TOKEN   【可选】前端要带的口令，防止被随意调用
 *   ALLOW_PREFIX 【可选】允许写入的路径前缀，默认 文案稿/
 *
 * 接口：
 *   GET  /          健康检查
 *   POST /api/save  body: { files:[{path,content}], message }
 */

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
  'Access-Control-Allow-Headers': 'Content-Type,X-Save-Token'
};

function json(data, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { 'Content-Type': 'application/json; charset=utf-8', ...CORS }
  });
}

export default {
  async fetch(request, env) {
    if (request.method === 'OPTIONS') return new Response(null, { status: 204, headers: CORS });

    const url = new URL(request.url);
    if (url.pathname === '/' || url.pathname === '') {
      return json({ ok: true, service: 'zz-kb-save', repo: (env.GH_OWNER || '') + '/' + (env.GH_REPO || '') });
    }
    if (url.pathname === '/api/save' && request.method === 'POST') {
      try { return json(await save(request, env)); }
      catch (e) { return json({ ok: false, error: String(e && e.message || e) }, 500); }
    }
    return json({ ok: false, error: 'not found' }, 404);
  }
};

async function save(request, env) {
  if (env.SAVE_TOKEN) {
    const got = request.headers.get('X-Save-Token') || '';
    if (got !== env.SAVE_TOKEN) return { ok: false, error: '口令不对（X-Save-Token）' };
  }
  if (!env.GH_TOKEN || !env.GH_OWNER || !env.GH_REPO) {
    return { ok: false, error: '服务端未配置 GH_TOKEN / GH_OWNER / GH_REPO' };
  }

  let body;
  try { body = await request.json(); }
  catch (e) { return { ok: false, error: '请求体不是 JSON' }; }

  const files = Array.isArray(body.files) ? body.files : [];
  if (!files.length) return { ok: false, error: '没有要保存的文件' };

  const allow = (env.ALLOW_PREFIX || '文案稿/').split(',').map(s => s.trim()).filter(Boolean);
  for (const f of files) {
    if (!f.path || typeof f.content !== 'string') return { ok: false, error: '文件字段不完整' };
    if (!/\.md$/.test(f.path)) return { ok: false, error: '只允许保存 .md 文案稿：' + f.path };
    if (!allow.some(p => f.path.startsWith(p))) return { ok: false, error: '路径不在允许范围：' + f.path };
    if (f.content.length > 200000) return { ok: false, error: '文件过大：' + f.path };
  }

  const branch = env.GH_BRANCH || 'main';
  const api = 'https://api.github.com/repos/' + env.GH_OWNER + '/' + env.GH_REPO;
  const H = {
    Authorization: 'Bearer ' + env.GH_TOKEN,
    Accept: 'application/vnd.github+json',
    'User-Agent': 'zz-kb-save',
    'Content-Type': 'application/json'
  };
  async function gh(path, method, payload) {
    const r = await fetch(api + path, { method, headers: H, body: payload ? JSON.stringify(payload) : undefined });
    const t = await r.text();
    let j = null; try { j = JSON.parse(t); } catch (e) {}
    if (!r.ok) throw new Error('GitHub ' + r.status + '：' + (j && j.message ? j.message : t.slice(0, 200)));
    return j;
  }

  // 1) 当前分支最新 commit
  const ref = await gh('/git/ref/heads/' + branch, 'GET');
  const baseSha = ref.object.sha;
  const commit = await gh('/git/commits/' + baseSha, 'GET');
  const baseTree = commit.tree.sha;

  // 2) 建一棵新树（content 直接给，GitHub 会自动建 blob）
  const tree = files.map(f => ({ path: f.path, mode: '100644', type: 'blob', content: f.content }));
  const newTree = await gh('/git/trees', 'POST', { base_tree: baseTree, tree });

  // 3) 提交并移动分支
  const msg = body.message || '在线保存文案稿';
  const newCommit = await gh('/git/commits', 'POST', { message: msg, tree: newTree.sha, parents: [baseSha] });
  await gh('/git/refs/heads/' + branch, 'PATCH', { sha: newCommit.sha });

  return {
    ok: true,
    commit: newCommit.sha,
    files: files.map(f => f.path),
    url: 'https://github.com/' + env.GH_OWNER + '/' + env.GH_REPO + '/commit/' + newCommit.sha
  };
}
