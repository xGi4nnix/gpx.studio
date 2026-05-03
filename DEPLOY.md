# Deploy gpx.studio über Portainer

Dieses Repo ist als **Stack from Git** in Portainer deploybar. Der Build läuft im
Container (Multi-Stage: `node` → statische Dateien → `nginx:alpine`), kein
Node-Prozess läuft im Betrieb — nur ein schlanker nginx, der die fertig
prerenderte SvelteKit-Site ausliefert.

## Was passiert beim Deploy

```
gpx (TS lib)         ┐
                     ├─►  npm run build  ─►  website/build/  ─►  nginx:alpine  ─►  Port 80 (intern)
website (SvelteKit)  ┘
```

Der Container hört intern auf Port 80 und wird per `docker-compose.yml`
auf dem Host auf `${HOST_PORT}` gemappt (default `3000`).

---

## 1. Erst-Deploy in Portainer

1. **Portainer öffnen → Stacks → Add stack**.
2. Im Reiter **Repository** auswählen.
3. Felder ausfüllen:
   - **Name**: `gpx-studio`
   - **Repository URL**: `https://github.com/xGi4nnix/gpx.studio.git`
     (Falls privat: Authentication aktivieren und PAT/Deploy-Key hinterlegen.)
   - **Repository reference**: `refs/heads/main`
   - **Compose path**: `docker-compose.yml`
4. **Environment variables** (unten in der Maske, *nicht* in der Compose-Datei):

   | Key                    | Value                  |
   | ---------------------- | ---------------------- |
   | `PUBLIC_MAPTILER_KEY`  | `t6t0Eq90DX931I7CZMzt` |
   | `HOST_PORT`            | `3000` *(optional)*    |
   | `BASE_PATH`            | *(leer lassen)*        |

   > Diese Variablen werden beim `docker compose build` als Build-Args an den
   > Dockerfile durchgereicht. Der MapTiler-Key wird in den Client-Bundle
   > eingebacken — das ist bei MapTiler so vorgesehen; sichere ihn ggf. in der
   > MapTiler-Konsole per Domain-Restriction ab.

5. **Deploy the stack** klicken. Beim ersten Mal dauert der Build je nach
   vServer-CPU 2–6 Minuten (Node-Module + SvelteKit-Build).

Wenn der Stack auf grün geht, ist gpx.studio unter
`http://<vserver-ip>:3000` erreichbar.

---

## 2. Domain davorschalten

Da der Container nur auf einem Port lauscht, brauchst du noch HTTPS + Domain.
Drei gängige Wege auf Portainer-vServern:

### a) Du hast schon einen Reverse Proxy (nginx/Caddy/Traefik)

Einfach einen Vhost auf `gpx.deinedomain.de` zeigen lassen, der intern auf
`http://127.0.0.1:3000` proxyt. Beispielhafter Caddy-Block:

```caddy
gpx.deinedomain.de {
    reverse_proxy 127.0.0.1:3000
}
```

### b) Nginx Proxy Manager (auch als Stack auf Portainer beliebt)

`Add Proxy Host` → Domain `gpx.deinedomain.de`, Forward Hostname
`<container-name oder host-ip>`, Forward Port `3000`, SSL → "Request a new
certificate" (Let's Encrypt).

### c) Du hast noch nichts — sag mir Bescheid

Dann erweitere ich den Stack um Caddy mit Auto-HTTPS, dann ist nur noch ein
DNS-A-Record nötig.

---

## 3. Update / Re-Deploy nach git push

In Portainer:

1. **Stacks → gpx-studio**
2. Reiter **Editor** → ganz unten **Pull and redeploy** (oder
   **Pull image and redeploy** je nach Version).

Portainer zieht dann den aktuellen Stand von `main`, baut neu und tauscht den
Container aus. Downtime: kurz (< 10 s) während nginx restartet.

> Auto-Update via Webhook ist möglich (Stack-Settings → "Automatic updates"),
> aber erstmal nicht aktiviert — wie besprochen.

---

## 4. Lokal testen (vor dem Push)

Auf einem Rechner mit Docker:

```bash
# .env existiert schon mit deinem MapTiler-Key (gitignored).
docker compose up --build
# → http://localhost:3000
```

Beenden mit `Ctrl+C`, aufräumen mit `docker compose down`.

---

## 5. Eigene Anpassungen pflegen

Du arbeitest auf deinem Fork (`xGi4nnix/gpx.studio`). Empfohlener Flow:

```bash
# Änderungen in einem Branch
git checkout -b feature/eigene-anpassung
# ... Code editieren (z.B. website/src/...) ...
git commit -am "Branding angepasst"
git push origin feature/eigene-anpassung

# In main mergen wenn fertig
git checkout main
git merge feature/eigene-anpassung
git push origin main
```

Danach in Portainer auf **Pull and redeploy** klicken.

### Upstream-Updates ziehen

Damit du Bugfixes/Features vom Original (`gpxstudio/gpx.studio`) bekommst:

```bash
git fetch upstream
git merge upstream/main      # oder: git rebase upstream/main
# Konflikte lösen, falls deine Änderungen dieselben Stellen berühren
git push origin main
```

---

## 6. Troubleshooting

**Build bricht ab mit `PUBLIC_MAPTILER_KEY must be set`**
→ Env-Var in Portainer nicht gesetzt. Stack-Editor → Environment variables
prüfen.

**Karte lädt nicht / 401 von api.maptiler.com**
→ Key falsch oder in der MapTiler-Konsole nicht für die Domain freigegeben.
Key in MapTiler → Account → Keys nachsehen oder Domain-Restriction lockern.

**404 auf Unterseiten (z.B. `/help`)**
→ Reverse Proxy passt URLs nicht durch. Stelle sicher, dass dein Proxy den
Pfad unverändert weiterleitet (kein Pfad-Stripping).

**Port 3000 belegt**
→ `HOST_PORT` in den Stack-Env-Vars auf etwas anderes setzen, z.B. `3010`.

**Build ist langsam**
→ Normal beim ersten Mal. Spätere Re-Deploys sind dank Docker-Layer-Cache
deutlich schneller (typischerweise < 90 s).
