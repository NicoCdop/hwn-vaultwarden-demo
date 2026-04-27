# hwn-vaultwarden-demo

Despliegue DEMO de [Vaultwarden](https://github.com/dani-garcia/vaultwarden) en [Railway](https://railway.com).

> **No es producción.** No almacenar credenciales reales.

## Stack

- **Imagen**: `vaultwarden/server:latest` (passthrough vía `Dockerfile`)
- **Hosting**: Railway (build desde Dockerfile, autodeploy en push a `main`)
- **Persistencia**: Railway Volume montado en `/data`
- **DB**: SQLite (default, en el volumen)
- **TLS**: dominio `*.up.railway.app` gestionado por Railway

Ver `CLAUDE.md` para decisiones de arquitectura, aprendizajes y checklist de promoción a producción.

## Setup rápido

Requisitos: cuenta en Railway, Railway CLI instalada (`brew install railway`), repo de GitHub conectado.

```bash
# 1. Login
railway login

# 2. Crear proyecto y linkearlo a este directorio
railway init   # o: railway link <project-id>

# 3. Agregar volumen para /data (vía dashboard o CLI)
#    Railway → Service → Volumes → New Volume → mount path: /data

# 4. Setear variables mínimas
railway variables --set "ADMIN_TOKEN=<argon2-phc>" \
                  --set "SIGNUPS_ALLOWED=true" \
                  --set "INVITATIONS_ALLOWED=true"

# 5. Push y dejar que Railway construya el Dockerfile
git push origin main

# 6. Generar dominio público
railway domain

# 7. Setear DOMAIN con la URL generada (sin slash final)
railway variables --set "DOMAIN=https://<service>.up.railway.app"

# 8. Acceder al admin panel: https://<service>.up.railway.app/admin
```

## Generar `ADMIN_TOKEN`

```bash
docker run --rm vaultwarden/server /vaultwarden hash
```

Pega la passphrase que quieras usar; copia el PHC string completo (`$argon2id$v=19$...`) como `ADMIN_TOKEN`.

## Estructura

```
.
├── Dockerfile          # FROM vaultwarden/server:latest
├── railway.json        # build=DOCKERFILE + deploy config
├── .env.example        # docs de todas las env vars relevantes
├── CLAUDE.md           # contexto + decisiones + aprendizajes
└── README.md
```
