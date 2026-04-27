# CLAUDE.md — hwn-vaultwarden-demo

## Propósito del repo

Despliegue **DEMO** de [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (servidor Bitwarden alternativo en Rust) en **Railway**, con dos objetivos:

1. Validar que la arquitectura funciona end-to-end (acceso vía HTTPS, persistencia, panel admin, web vault, app móvil).
2. Generar **aprendizajes documentados** para más tarde promover a un despliegue de producción (probablemente con dominio propio, Postgres gestionado, backups y SMTP real).

> **No es producción.** Datos pueden borrarse. No usar para credenciales reales.

## 📍 Estado actual (2026-04-27)

**DEMO desplegada y funcional en cuenta `automations@hirewithnear.com`**:

| | Valor |
|---|---|
| Project | `Vaultwarden` (id `fc1438b0-837a-4553-adfe-e216c932bd13`) |
| Environment | `production` (id `7056467c-57cd-4e66-ac49-80299f89ab9d`) |
| Service | `Vaultwarden` (id `20ce1121-a682-4e6e-896c-0189e1a3f1fb`), image `vaultwarden/server:latest`, versión actual `1.35.8` |
| Volume | `vaultwarden-volume` montado en `/data` (id `047581c3-66bb-4a42-861c-28faf3b3e105`) |
| Service Domain | `near-vaultwarden.up.railway.app` (id `eaa832e9-c5a8-44c5-9421-8b3c00f89e53`, targetPort=80) |
| URL pública | `https://near-vaultwarden.up.railway.app` |
| Healthcheck | `/alive` → 200 |
| Email outbound | SMTP2GO en **puerto 8025** (ver gotcha abajo) |
| Hardening | `ADMIN_TOKEN` Argon2id PHC, `SIGNUPS_ALLOWED=true` (cerrar tras onboarding), `INVITATIONS_ALLOWED=true`, `LOG_LEVEL=info` |
| Estado de uso | 4 usuarios registrados (Nicolas + 3 colegas), 1 organización (`HireWithNear`) |

> **Cuenta vieja (`nchirino@dataonpulse.com`)**: el proyecto `hwn-vaultwarden-demo` con dominio `vaultwarden-production-99a1.up.railway.app` quedó residual. **Borrar desde el dashboard de esa cuenta** para no consumir recursos.

**TODOs pendientes**:
- Cerrar `SIGNUPS_ALLOWED=false` cuando todos los miembros previstos estén registrados.
- Decidir si se promueve este DEMO a producción o se rebuilda con tag pinneado + Postgres.

## Decisiones de arquitectura

| Decisión | Elección DEMO | Razón | Plan para prod |
|---|---|---|---|
| Imagen base | `vaultwarden/server:latest` (oficial dani-garcia) | Mantenida activamente, multi-arch, lista para producción | Pin a tag inmutable (`vaultwarden/server:1.x.y`) + verificar firma |
| Mecanismo de deploy | **Dockerfile passthrough** (`FROM vaultwarden/server:latest`) | Railway `railway.json` NO soporta deploy directo desde registry público; un Dockerfile mínimo es la forma más limpia de IaC | Misma estrategia, pero con tag pinneado |
| Base de datos | **SQLite** sobre volumen `/data` | Default de Vaultwarden, sin servicios extra, rápido para 1-5 usuarios | **Postgres gestionado de Railway** + `DATABASE_URL` (SQLite ha tenido issues conocidos con volúmenes en Railway) |
| Persistencia | Railway Volume montado en `/data` (5 GB en Hobby) | Único storage persistente que ofrece Railway. Plan Trial solo da 0.5 GB | Volume + backup programado a S3/B2 (rclone o `vaultwarden`'s `BACKUP_DIR`) |
| TLS | Dominio `*.up.railway.app` con TLS gestionado por Railway | Gratis, instantáneo, válido para web crypto API de Bitwarden | Dominio propio + TLS de Railway o Cloudflare delante |
| WebSocket | Integrado en el mismo puerto (Vaultwarden ≥1.29) | Railway proxy soporta WS upgrade automático sin config | Igual |
| Admin token | **Argon2id PHC** (nunca plaintext) | Recomendación oficial Vaultwarden | Igual + rotación periódica + 2FA en mantenedor |
| Signups | `SIGNUPS_ALLOWED=false` tras primer registro | Evita squatting | Mantener cerrado, solo invitaciones |
| SMTP | Sin SMTP en DEMO (no envíos transaccionales) | Simplifica setup; invitaciones manuales | Configurar SES/Mailgun/Postmark con DKIM |

## Variables de entorno críticas

Documentadas en `.env.example`. Las **mínimas** para que arranque en Railway:

| Var | Valor DEMO | Notas |
|---|---|---|
| `DOMAIN` | `https://<service>.up.railway.app` | **Sin slash final**. Sin esto, web vault y notificaciones rompen |
| `ADMIN_TOKEN` | Argon2 PHC string | Generar con `vaultwarden hash` o `argon2` CLI; **nunca commitearlo** |
| `SIGNUPS_ALLOWED` | `true` (solo durante primer registro) → luego `false` | |
| `INVITATIONS_ALLOWED` | `true` | Permite invitar desde admin panel |
| `RAILWAY_RUN_UID` | `0` | Solo si la imagen corre non-root y hay errores de permisos sobre el volumen. **No fue necesario en la cuenta nueva** (la imagen escribe `/data` sin problemas) |
| `ROCKET_PORT` | `80` (default de la imagen) | Railway proxy detecta `EXPOSE` del Dockerfile padre |
| `LOG_LEVEL` | `info` | Subir a `debug` solo para troubleshooting puntual (especialmente para SMTP — `rustls`/`lettre` solo loguean en debug) |

### SMTP (outbound email vía SMTP2GO)

| Var | Valor DEMO | Notas |
|---|---|---|
| `SMTP_HOST` | `mail.smtp2go.com` | |
| `SMTP_PORT` | **`8025`** | **NO usar 2525/587/465** desde Railway us-west2 — los paquetes se dropean silenciosamente (gotcha documentado abajo) |
| `SMTP_SECURITY` | `starttls` | SMTP2GO acepta STARTTLS en cualquier puerto, incluido 8025 |
| `SMTP_USERNAME` | (SMTP user creado en SMTP2GO) | Puede ser un email o username arbitrario |
| `SMTP_PASSWORD` | (password generado por SMTP2GO) | Setear con single quotes en bash si tiene `$`, `@`, etc. |
| `SMTP_FROM` | `nicolas.chirino@hirewithnear.com` | Debe ser un sender verificado en SMTP2GO (idealmente dominio verificado con SPF+DKIM) |
| `SMTP_FROM_NAME` | `Vaultwarden HireWithNear` | Display name |

## Aprendizajes (actualizar a medida que avanzamos)

> Esta sección es la razón por la que existe este repo: capturar todo lo no obvio que descubramos.

### Sobre Railway

- **`railway.json` no permite declarar volúmenes ni image-from-registry.** Solo `build` (RAILPACK/DOCKERFILE), `deploy` (startCommand, healthcheck, restart), y `environments`. Volúmenes se crean con `railway volume add` (CLI) o dashboard.
- **Una sola volume por servicio** por proyecto/tier.
- **Cap por tier** para volume size: Trial 0.5 GB, Hobby 5 GB, Pro 50 GB.
- **`RAILWAY_RUN_UID=0`** es el escape hatch documentado cuando la imagen no es root y hay errores de permisos sobre el mount path.
- **Cambios en `railway.json` redeployan**, pero los cambios en variables aplican vía CLI/dashboard de forma independiente.
- **WebSocket upgrade** lo maneja el proxy HTTPS de Railway sin config extra.

### Sobre Vaultwarden

- Versiones modernas (≥1.29) integraron WebSocket en el puerto principal — ya no se expone `3012` aparte.
- `ADMIN_TOKEN` puede ser plaintext, pero **siempre** preferir Argon2id PHC (`$argon2id$v=19$...`). El binario incluye `vaultwarden hash` para generarlo.
- Volume **debe** ser `/data` (no `/app/data`) — esa es la ruta que el binario escribe (db.sqlite3, attachments/, sends/, rsa_key.pem, icon_cache/).
- `DOMAIN` debe incluir esquema (`https://`) y **no** terminar con `/`.

### Sobre el flow de deploy

- **Generar `ADMIN_TOKEN`**: `docker run --rm vaultwarden/server /vaultwarden hash` **falla en modo no-interactivo** (panic: "No such device or address" — necesita TTY). Workaround: usar `argon2` CLI directo con los params del preset Bitwarden:
  ```bash
  brew install argon2
  echo -n "$PASSPHRASE" | argon2 "$(openssl rand -base64 32)" -e -id -k 65540 -t 3 -p 4
  ```
  El output es un PHC string `$argon2id$v=19$m=65540,t=3,p=4$...$...` listo para pegar en `ADMIN_TOKEN`.

- **GOTCHA: variables con `$` literales** se corrompen si se setean vía el MCP `set-variables` (que internamente arma un comando shell). Bash expande `$argon2id`, `$v`, `$m` como variables vacías y deja el valor truncado. **Siempre** setear PHC strings con bash directo y single quotes:
  ```bash
  railway variables --set 'ADMIN_TOKEN=$argon2id$v=19$m=...$...$...' --service <name> --skip-deploys
  ```
  Verificar con `railway variables --service <name> --kv | grep ADMIN_TOKEN` (no con la tabla, que enmascara).

- **GOTCHA: `railway service [NAME] delete`** (sintaxis posicional, marcada como deprecated en help) opera silenciosamente sobre el **servicio linkeado** ignorando el `[NAME]`. **Usar siempre la flag**: `railway service delete --service <name> --yes`.

- **`railway add --repo <user>/<repo>`** falla con "Unauthorized" si la GitHub App de Railway no está autorizada al repo. Path de fix: dashboard → Account → Integrations → install Railway GitHub App. Para DEMO se evitó usando `--image` (deploy desde registry público sin GitHub).

- **`railway add --image vaultwarden/server:latest`** crea el servicio listo para correr — sin Dockerfile, sin build step, sin GitHub. Trade-off: no hay auto-deploy en push (cada actualización requiere `railway service redeploy` o re-`add`). Para DEMO es óptimo.

- **El primer `railway up` antes de tener servicio** muestra "Failed to deploy" desde el MCP, pero **sí crea un servicio** con una deployment FAILED. Limpieza necesaria si pasa.

- **Volúmenes en Railway no son gestionables vía CLI v4.x** — solo dashboard (Service → Settings → Volumes → New Volume → mount path `/data`). Adjuntar/cambiar un volumen dispara redeploy automáticamente.

- **Servicios image-based ignoran `railway.json`** para `build.builder` (lógico, no hay build), pero respetan `deploy.*` (healthcheck, restart policy). Nuestro `railway.json` queda como referencia de prod, no como config activa de la DEMO.

- **GOTCHA crítico — image-based deploys NO autodetectan `EXPOSE`**. La domain se crea con `targetPort: null` y el proxy devuelve `502 Application failed to respond` aunque el contenedor esté `RUNNING`. Verificación + fix vía GraphQL:
  ```bash
  # Inspect
  curl -sS -X POST https://backboard.railway.com/graphql/v2 \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"query":"query($p:String!){domains(projectId:$p,environmentId:\"<env-id>\",serviceId:\"<svc-id>\"){serviceDomains{id domain targetPort}}}","variables":{"p":"<project-id>"}}'
  # Fix
  curl -sS -X POST https://backboard.railway.com/graphql/v2 \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
    -d '{"query":"mutation($i:ServiceDomainUpdateInput!){serviceDomainUpdate(input:$i)}","variables":{"i":{"serviceDomainId":"<sd-id>","domain":"<domain>","environmentId":"<env-id>","serviceId":"<svc-id>","targetPort":80}}}'
  ```

- **MCP de Railway (v actual) no expone volúmenes ni domain target port** — pero la **GraphQL API pública** (`https://backboard.railway.com/graphql/v2`) sí los gestiona. Auth: bearer token desde `~/.railway/config.json` → `user.accessToken`. Mutations clave: `volumeCreate(input:VolumeCreateInput)` y `serviceDomainUpdate(input:ServiceDomainUpdateInput)`. Schema introspectable con `__type(name:"...")`. Esto evita salidas al dashboard durante deploys IaC.

- **Adjuntar un volumen NO siempre redeploya solo** — disparar manual con `railway service redeploy --service <name> --yes` si la nueva deployment no aparece en ~30s.

- **Endpoints de healthcheck Vaultwarden**: `/alive` devuelve un timestamp ISO (200 OK). No requiere auth. Útil para `healthcheckPath`.

- **Auth a GraphQL**: el token guardado en `~/.railway/config.json` (`accessToken`) es **personal account token** — válido para todas las operaciones bajo esa cuenta. Para CI/CD usar tokens scoped (Project Tokens) creados desde dashboard.

- **Matiz al gotcha de `targetPort=null`**: en la cuenta nueva (`automations@hirewithnear.com`) el deploy *sí* respondía `/alive` con `targetPort=null`, probablemente porque la variable `PORT=80` (autoinjectada por Railway en algunos servicios) le sirve de hint al proxy. Igual conviene **fijar `targetPort=80` explícitamente** vía `serviceDomainUpdate` para no depender de ese fallback no-documentado.

### Sobre SMTP outbound (SMTP2GO desde Railway)

- **GOTCHA crítico — Railway us-west2 dropea silenciosamente conexiones TCP a `mail.smtp2go.com` en puertos 2525, 587 y 465**. Sin RST, sin timeout del kernel, sin error de lettre/Vaultwarden — la conexión cuelga indefinidamente (>90s y sigue). Síntoma diagnóstico con `LOG_LEVEL=debug`: lettre completa la carga de root certs (`rustls add_parsable_certificates processed 150 valid certs`) y después **silencio absoluto**, ningún log de TLS handshake o EHLO.
- **Workaround validado**: usar el puerto **`8025`** (alternativo que SMTP2GO advertised exactamente para casos de cloud egress filtering). Funcionó al primer intento desde Railway, handshake TLS y AUTH completos en <2s.
- **No probados** (pero teóricamente también inmunes al filtro): `80`, `443`, `8465`. Si 8025 falla en el futuro, intentar primero `8465` con `force_tls`.
- **Verificación rápida** del estado de SMTP sin tener que mandar invitaciones reales:
  ```bash
  COOKIE=$(mktemp); TOKEN='<admin-passphrase>'
  curl -sS -c "$COOKIE" -X POST https://<domain>/admin --data-urlencode "token=$TOKEN" -o /dev/null
  curl -sS --max-time 30 -b "$COOKIE" -X POST https://<domain>/admin/test/smtp \
    -H 'Content-Type: application/json' -d '{"email":"<your-email>"}' -w "\nHTTP %{http_code} | %{time_total}s\n"
  rm -f "$COOKIE"
  ```
  - HTTP 200 en <3s → SMTP funciona.
  - Cuelga >30s con HTTP 000 → estás en el bug del puerto-bloqueado.
  - HTTP 401 → tu cookie expiró (redeploy reciente), volver a hacer login.
- **Para enviar emails ad-hoc** desde local (anuncios, tests, debugging) usando SMTP2GO en puerto 8025:
  ```python
  import smtplib
  from email.message import EmailMessage
  msg = EmailMessage()
  msg["From"]    = "<sender-name> <sender@hirewithnear.com>"
  msg["To"]      = "alice@x.com, bob@y.com"
  msg["Subject"] = "..."
  msg.set_content("body...")
  with smtplib.SMTP("mail.smtp2go.com", 8025, timeout=30) as s:
      s.starttls()
      s.login("<smtp-user>", "<smtp-password>")
      s.send_message(msg)
  ```

### Sobre el admin panel API (introspección sin DB)

- El admin panel de Vaultwarden es session-based (cookie tras `POST /admin` con `token=<plaintext>`). Una vez autenticado:
  - `GET /admin/users` con `Accept: application/json` devuelve **JSON** con todos los usuarios (campos en camelCase: `id`, `email`, `name`, `createdAt`, `lastActive`, `userEnabled`, `organizations[].name`, etc.).
  - `GET /admin/organizations/overview` devuelve **HTML** (no hay variant JSON; se puede scrapear con `pup`/regex si hace falta).
  - `POST /admin/test/smtp` con `{"email":"..."}` envía un test email y devuelve 200 si SMTP relay aceptó.
  - `GET /admin/diagnostics` HTML; al final del body hay un bloque JSON con `db_type`, `current_release`, `latest_release`, `dns_resolved`, `has_http_access`, `running_within_container`, etc. Útil para health/observability programmatic.
- Esto evita necesidad de exec into container o acceso directo a SQLite para introspección.

## Flujo de trabajo en este repo

```
local edit  →  commit  →  push origin main  →  Railway auto-deploy (GitHub integration)
```

Para cambios solo de env vars: usar `railway variables --set KEY=VALUE` (re-deploy automático salvo `--skip-deploys`).

## Scripts / comandos útiles

```bash
# === Generar ADMIN_TOKEN Argon2id PHC (versión que SÍ funciona) ===
# El comando docker run --rm vaultwarden/server /vaultwarden hash falla
# en modo no-interactivo. Usar argon2 CLI directo con preset Bitwarden:
brew install argon2  # solo la primera vez
PASSPHRASE=$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9' | head -c 32)
SALT=$(openssl rand -base64 16)
PHC=$(printf '%s' "$PASSPHRASE" | argon2 "$SALT" -e -id -k 65540 -t 3 -p 4)
echo "ADMIN passphrase (guardar fuera del repo): $PASSPHRASE"
echo "PHC para Railway: $PHC"
railway variables --service Vaultwarden --skip-deploys --set "ADMIN_TOKEN=$PHC"

# === Linkear / inspeccionar / desplegar ===
railway link --project fc1438b0-837a-4553-adfe-e216c932bd13 --environment production
railway whoami                                          # confirma cuenta linkeada
railway status                                          # project/env/service actual
railway logs --service Vaultwarden                      # logs en vivo
railway variables --service Vaultwarden --kv            # listar vars sin máscara
railway redeploy --service Vaultwarden --yes            # forzar redeploy

# === Setear variables (recordar single quotes para valores con $/@) ===
railway variables --service Vaultwarden --skip-deploys \
  --set 'KEY1=valor1' \
  --set 'KEY2=valor con $ literal'
railway redeploy --service Vaultwarden --yes

# === Test rápido de SMTP (ver "Sobre SMTP outbound" arriba) ===
COOKIE=$(mktemp); TOKEN='<admin-passphrase-plaintext>'
curl -sS -c "$COOKIE" -X POST https://near-vaultwarden.up.railway.app/admin \
  --data-urlencode "token=$TOKEN" -o /dev/null
curl -sS --max-time 30 -b "$COOKIE" -X POST \
  https://near-vaultwarden.up.railway.app/admin/test/smtp \
  -H 'Content-Type: application/json' \
  -d '{"email":"nicolas.chirino@hirewithnear.com"}' \
  -w "\nHTTP %{http_code} | %{time_total}s\n"
rm -f "$COOKIE"

# === GraphQL: fijar targetPort=80 en el dominio (image-based deploy) ===
TOKEN=$(jq -r '.user.token // .user.accessToken' ~/.railway/config.json)
curl -sS -X POST https://backboard.railway.com/graphql/v2 \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"query":"mutation($i:ServiceDomainUpdateInput!){serviceDomainUpdate(input:$i)}","variables":{"i":{"serviceDomainId":"eaa832e9-c5a8-44c5-9421-8b3c00f89e53","domain":"near-vaultwarden.up.railway.app","environmentId":"7056467c-57cd-4e66-ac49-80299f89ab9d","serviceId":"20ce1121-a682-4e6e-896c-0189e1a3f1fb","targetPort":80}}}'
```

## Checklist antes de promover a producción

- [ ] Pinneo de imagen a tag inmutable (no `latest`)
- [ ] Migración SQLite → Postgres gestionado
- [ ] Backup automático del volume + DB (cron + storage externo)
- [ ] SMTP configurado (DKIM+SPF en dominio)
- [ ] `SIGNUPS_ALLOWED=false`, `INVITATIONS_ALLOWED=true`
- [ ] `ADMIN_TOKEN` Argon2 + rotado tras DEMO
- [ ] Dominio propio + TLS verificado
- [ ] Rate limiting (`LOGIN_RATELIMIT_*`) configurado
- [ ] Monitoreo (uptime + error rate)
- [ ] Secret de `ADMIN_TOKEN` y `DATABASE_URL` solo en Railway (nunca en repo)
- [ ] Probar `restore from backup` antes de que sea necesario
- [ ] Revisar [security audit checklist de Vaultwarden](https://github.com/dani-garcia/vaultwarden/wiki/Hardening-Guide)
