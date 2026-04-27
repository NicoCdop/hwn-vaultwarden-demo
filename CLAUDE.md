# CLAUDE.md — hwn-vaultwarden-demo

## Propósito del repo

Despliegue **DEMO** de [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (servidor Bitwarden alternativo en Rust) en **Railway**, con dos objetivos:

1. Validar que la arquitectura funciona end-to-end (acceso vía HTTPS, persistencia, panel admin, web vault, app móvil).
2. Generar **aprendizajes documentados** para más tarde promover a un despliegue de producción (probablemente con dominio propio, Postgres gestionado, backups y SMTP real).

> **No es producción.** Datos pueden borrarse. No usar para credenciales reales.

## 📍 Checkpoint / Resume here (2026-04-26 21:00 GMT-4)

**Última acción**: deploy DEMO funcionando en cuenta vieja. Usuario decidió **migrar a otra cuenta de Railway**. Hizo `railway logout` + `railway login` con la cuenta nueva + `railway unlink`. Está reiniciando la terminal.

**Estado en cuenta VIEJA** (sigue corriendo, hay que apagarlo desde dashboard de esa cuenta cuando se confirme la migración):
- Project: `hwn-vaultwarden-demo` (id `fec8044b-9784-4630-96cd-bf8d18e5ab9a`)
- Service: `vaultwarden`, image `vaultwarden/server:latest`
- Volumen: `vaultwarden-volume` montado en `/data` (id `63a277a8-bccc-4b38-a503-4b89b4969d98`)
- Domain: `https://vaultwarden-production-99a1.up.railway.app` (targetPort 80)
- Email account: `nchirino@dataonpulse.com`

**Estado en cuenta NUEVA**: aún sin proyecto. Token de la cuenta vieja en `~/.railway/config.json` quedó sobreescrito por el nuevo login.

**Próxima acción cuando la sesión se reanude**:
1. Verificar login de la cuenta nueva: `mcp__Railway__check-railway-status` + `mcp__Railway__list-projects` (debe mostrar los proyectos de la cuenta nueva, no `hwn-vaultwarden-demo`).
2. Preguntar al usuario: ¿crear `hwn-vaultwarden-demo` desde cero en la cuenta nueva, o linkear a un proyecto existente?
3. Si "desde cero", replicar todo el flujo (esta vez sin sorpresas, ya está documentado abajo):
   - `railway add --service vaultwarden --image vaultwarden/server:latest`
   - **Regenerar** `ADMIN_TOKEN` Argon2 con `argon2` CLI (no reutilizar el viejo) — pasar al usuario para que lo guarde.
   - `railway variables --set 'ADMIN_TOKEN=...'` con single quotes (gotcha del `$`)
   - `railway variables --set` para `SIGNUPS_ALLOWED=true`, `INVITATIONS_ALLOWED=true`, `LOG_LEVEL=info`, `RAILWAY_RUN_UID=0`, `ROCKET_PORT=80`
   - `mcp__Railway__generate-domain` → `set DOMAIN=https://...`
   - Crear volumen vía GraphQL (`volumeCreate` mutation, ver gotchas abajo)
   - **Setear `targetPort: 80`** vía `serviceDomainUpdate` mutation (gotcha crítico de image-based deploys)
   - `railway service redeploy --service vaultwarden --yes`
   - Verificar `/alive` → 200
4. Recordar al usuario: ir al dashboard de la cuenta vieja a **borrar el proyecto `hwn-vaultwarden-demo`** para no consumir crédito.

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
| `RAILWAY_RUN_UID` | `0` | Solo si la imagen corre non-root y hay errores de permisos sobre el volumen |
| `ROCKET_PORT` | `80` (default de la imagen) | Railway proxy detecta `EXPOSE` del Dockerfile padre |
| `LOG_LEVEL` | `info` | Subir a `debug` solo para troubleshooting puntual |

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

## Flujo de trabajo en este repo

```
local edit  →  commit  →  push origin main  →  Railway auto-deploy (GitHub integration)
```

Para cambios solo de env vars: usar `railway variables --set KEY=VALUE` (re-deploy automático salvo `--skip-deploys`).

## Scripts / comandos útiles

```bash
# Generar admin token Argon2
docker run --rm vaultwarden/server /vaultwarden hash

# Linkear este repo a Railway
railway link

# Ver logs en vivo
railway logs

# Listar variables
railway variables

# Setear variable
railway variables --set "DOMAIN=https://xxx.up.railway.app"
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
