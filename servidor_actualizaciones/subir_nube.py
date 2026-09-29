"""Sube las actualizaciones de RogerOS a la nube: funcionan aunque tu PC esté APAGADO.

  * Paquetes (.deb, de cualquier tamaño hasta 2 GB) -> GitHub Releases, en la versión "paquetes"
    de github.com/RogerXDyt/rogeros
  * Índice firmado (dists/) y clave pública -> Cloudflare (link fijo de siempre)
  * El Worker de Cloudflare redirige cada /pool/main/X.deb a su descarga en GitHub.

Seguridad: el índice va firmado con tu clave (que nunca sale de tu PC) e incluye la huella SHA256
de cada paquete. RogerOS rechaza cualquier paquete que no coincida, aunque alguien tocara GitHub.
"""
import glob, json, os, shutil, subprocess, sys, tempfile

sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(AQUI, "repo")
RT = os.path.join(os.path.dirname(os.path.dirname(AQUI)), "rogertube")
CFG = json.load(open(os.path.join(RT, "config.json"), encoding="utf-8"))
GH = r"C:\Program Files\GitHub CLI\gh.exe"
REPO_GH = "RogerXDyt/rogeros"
ETIQUETA = "paquetes"


def gh(*args, **kw):
    return subprocess.run([GH, *args], capture_output=True, text=True, encoding="utf-8", errors="replace", **kw)


# ---- 1. Paquetes a GitHub Releases
if gh("release", "view", ETIQUETA, "-R", REPO_GH).returncode != 0:
    r = gh("release", "create", ETIQUETA, "-R", REPO_GH, "--title", "Paquetes de actualización de RogerOS",
           "--notes", "Archivos que descarga el botón Actualizar de RogerOS. No hace falta bajarlos a mano.",
           "--latest=false")
    if r.returncode != 0:
        sys.exit("✘ No se pudo crear la versión 'paquetes' en GitHub:\n" + r.stderr)
subidos = {a["name"] for a in json.loads(gh("release", "view", ETIQUETA, "-R", REPO_GH, "--json", "assets").stdout)["assets"]}
for deb in sorted(glob.glob(os.path.join(REPO, "pool", "main", "*.deb"))):
    n = os.path.basename(deb)
    if n in subidos:
        continue
    print(f"» Subiendo {n} ({os.path.getsize(deb)/1e6:.1f} MB) a GitHub…")
    r = gh("release", "upload", ETIQUETA, deb, "-R", REPO_GH, "--clobber")
    if r.returncode != 0:
        sys.exit("✘ Falló la subida a GitHub:\n" + r.stderr)

# ---- 2. Índice firmado + Worker a Cloudflare
tmp = tempfile.mkdtemp(prefix="rogeros_nube_")
pub = os.path.join(tmp, "publico")
shutil.copytree(os.path.join(REPO, "dists"), os.path.join(pub, "dists"))
shutil.copy2(os.path.join(REPO, "rogeros.gpg"), pub)
with open(os.path.join(tmp, "worker.js"), "w", encoding="utf-8") as f:
    f.write(r"""export default {
  async fetch(req, env) {
    const u = new URL(req.url);
    if (!['GET', 'HEAD'].includes(req.method)) return new Response('No', { status: 405 });
    const m = u.pathname.match(/^\/pool\/main\/([A-Za-z0-9._+~-]+\.deb)$/);
    if (m) return Response.redirect('https://github.com/%s/releases/download/%s/' + m[1], 302);
    if (/^\/(dists\/[A-Za-z0-9._\/-]+|rogeros\.gpg)$/.test(u.pathname) && !u.pathname.includes('..'))
      return env.ASSETS.fetch(req);
    return new Response('No', { status: 404 });
  }
};
""" % (REPO_GH, ETIQUETA))
with open(os.path.join(tmp, "wrangler.json"), "w", encoding="utf-8") as f:
    json.dump({"name": "rogeros", "main": "worker.js", "compatibility_date": "2025-01-01",
               "assets": {"directory": "./publico", "binding": "ASSETS", "run_worker_first": True},
               "workers_dev": True, "preview_urls": False}, f, indent=2)
env = dict(os.environ, CLOUDFLARE_API_TOKEN=CFG["cf_token"], CLOUDFLARE_ACCOUNT_ID=CFG["cf_cuenta"],
           WRANGLER_SEND_METRICS="false", NODE_OPTIONS="--use-system-ca")
print("» Subiendo el índice firmado a Cloudflare…")
r = subprocess.run("npx --yes wrangler@4 deploy", cwd=tmp, env=env, shell=True,
                   capture_output=True, text=True, encoding="utf-8", errors="replace")
salida = (r.stdout or "") + (r.stderr or "")
shutil.rmtree(tmp, ignore_errors=True)
if r.returncode != 0:
    print(salida[-2500:])
    sys.exit("✘ No se pudo subir a Cloudflare")
print("✔ Actualizaciones en la nube. Ya no hace falta tener el PC encendido.")
