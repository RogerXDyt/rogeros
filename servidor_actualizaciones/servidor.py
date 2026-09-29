"""Servidor de actualizaciones de RogerOS (se ejecuta en tu PC con Windows).

Seguridad, pensada para que por aquí NO pueda entrar nada a tu PC:
  * Escucha solo en 127.0.0.1: desde tu red o desde internet no se puede conectar directamente.
  * Internet llega por un túnel de Cloudflare que SALE de tu PC: no hay que abrir puertos en el router.
  * Solo se puede LEER: GET/HEAD, solo dentro de la carpeta repo/, solo nombres de archivo válidos
    de un repositorio apt, sin listar carpetas, sin '..', sin archivos ocultos. Nada se escribe.
  * Las actualizaciones van FIRMADAS con tu clave (que nunca sale de tu PC). RogerOS rechaza todo
    lo que no lleve tu firma, aunque alguien consiguiera colarse en medio.
  * El Worker de Cloudflare vuelve a filtrar: solo GET/HEAD a /dists/, /pool/ y /rogeros.gpg.
"""
import http.server, json, os, re, socketserver, subprocess, sys, threading, time

sys.stdout.reconfigure(encoding="utf-8", line_buffering=True)
AQUI = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.join(AQUI, "repo")
PUERTO = 8791
NOMBRE_WORKER = "rogeros"
RT = os.path.join(os.path.dirname(os.path.dirname(AQUI)), "rogertube")   # reutiliza la cuenta de Cloudflare
CLOUDFLARED = os.path.join(RT, "cloudflared.exe")
CFG = json.load(open(os.path.join(RT, "config.json"), encoding="utf-8"))

RUTA_OK = re.compile(r"^/(dists/estable/(InRelease|Release|Release\.gpg|main/binary-(amd64|all)/Packages(\.gz|\.xz)?)"
                     r"|pool/main/[a-z0-9][a-z0-9.+-]*_[A-Za-z0-9.+~:-]+_(all|amd64)\.deb"
                     r"|rogeros\.gpg)$")


class SoloLectura(http.server.SimpleHTTPRequestHandler):
    server_version = "RogerOS"
    sys_version = ""

    def __init__(self, *a, **kw):
        super().__init__(*a, directory=REPO, **kw)

    def _ruta_valida(self):
        ruta = self.path.split("?", 1)[0]
        return bool(RUTA_OK.match(ruta)) and ".." not in ruta and "//" not in ruta

    def do_GET(self):
        if not self._ruta_valida():
            self.send_error(404); return
        super().do_GET()

    def do_HEAD(self):
        if not self._ruta_valida():
            self.send_error(404); return
        super().do_HEAD()

    def list_directory(self, path):          # nunca listar carpetas
        self.send_error(404); return None

    def _prohibido(self):
        self.send_error(405)
    do_POST = do_PUT = do_DELETE = do_PATCH = do_OPTIONS = _prohibido

    def log_message(self, fmt, *args):
        print(time.strftime("%H:%M:%S"), self.headers.get("CF-Connecting-IP", self.client_address[0]),
              fmt % args)


class Servidor(socketserver.ThreadingMixIn, http.server.HTTPServer):
    daemon_threads = True
    allow_reuse_address = True


# ---------------- link fijo con Cloudflare Workers (como RogerTube) ----------------
WORKER_JS = r"""export default { async fetch(req) {
  const u = new URL(req.url);
  const ok = /^\/(dists\/estable\/[A-Za-z0-9._\/-]+|pool\/main\/[A-Za-z0-9._+~:-]+\.deb|rogeros\.gpg)$/;
  if (!['GET', 'HEAD'].includes(req.method) || !ok.test(u.pathname) || u.pathname.includes('..'))
    return new Response('No', { status: 404 });
  const t = new URL(TARGET); u.hostname = t.hostname; u.protocol = 'https:'; u.port = ''; u.search = '';
  const r = await fetch(u.toString(), { method: req.method, headers: { 'User-Agent': 'RogerOS-Worker' } });
  const h = new Headers(r.headers); h.set('X-Content-Type-Options', 'nosniff');
  return new Response(r.body, { status: r.status, headers: h });
} };
"""


def cf_api(metodo, ruta, **kw):
    import requests
    try:
        import truststore; truststore.inject_into_ssl()
    except Exception:
        pass
    url = "https://api.cloudflare.com/client/v4/accounts/" + CFG["cf_cuenta"] + ruta
    h = {"Authorization": "Bearer " + CFG["cf_token"]}
    try:
        resp = requests.request(metodo, url, headers=h, timeout=60, **kw)
    except requests.exceptions.SSLError:
        resp = requests.request(metodo, url, headers=h, timeout=60, verify=False, **kw)
    j = resp.json()
    if not j.get("success"):
        raise RuntimeError(str(j.get("errors")))
    return j.get("result")


def subir_worker(url_tunel):
    js = "const TARGET = " + json.dumps(url_tunel) + ";\n" + WORKER_JS
    meta = json.dumps({"main_module": "worker.js", "compatibility_date": "2024-06-01"})
    cf_api("PUT", f"/workers/scripts/{NOMBRE_WORKER}",
           files={"metadata": (None, meta, "application/json"),
                  "worker.js": ("worker.js", js, "application/javascript+module")})
    sub = cf_api("GET", "/workers/subdomain")["subdomain"]
    cf_api("POST", f"/workers/scripts/{NOMBRE_WORKER}/subdomain", json={"enabled": True, "previews_enabled": False})
    return f"https://{NOMBRE_WORKER}.{sub}.workers.dev"


def lanzar_tunel():
    p = subprocess.Popen([CLOUDFLARED, "tunnel", "--url", f"http://127.0.0.1:{PUERTO}", "--no-autoupdate"],
                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, encoding="utf-8", errors="replace")
    for linea in p.stdout:
        m = re.search(r"https://[a-z0-9-]+\.trycloudflare\.com", linea)
        if m:
            try:
                link = subir_worker(m.group(0))
                print("\n" + "=" * 64 + f"\n  SERVIDOR DE ACTUALIZACIONES EN MARCHA\n  Link fijo: {link}\n"
                      "  Deja esta ventana abierta para que los RogerOS puedan actualizarse.\n" + "=" * 64 + "\n")
            except Exception as e:
                print("[worker] ERROR al actualizar el link fijo:", e)
            break
    for _ in p.stdout:      # seguir leyendo para que cloudflared no se bloquee
        pass


if __name__ == "__main__":
    if not os.path.exists(os.path.join(REPO, "dists", "estable", "InRelease")):
        print("Todavía no hay ninguna actualización publicada. Ejecuta primero PUBLICAR_ACTUALIZACION.bat")
        sys.exit(1)
    srv = Servidor(("127.0.0.1", PUERTO), SoloLectura)
    print(f"[RogerOS] sirviendo {REPO} (solo lectura) en 127.0.0.1:{PUERTO}")
    threading.Thread(target=lanzar_tunel, daemon=True).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
