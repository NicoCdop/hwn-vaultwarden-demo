# CLAUDE.md — hwn-vaultwarden-demo

## Propósito del repo

Despliegue **DEMO** de [Vaultwarden](https://github.com/dani-garcia/vaultwarden) (servidor Bitwarden alternativo en Rust) en **Railway**, con dos objetivos:

1. Validar que la arquitectura funciona end-to-end (acceso vía HTTPS, persistencia, panel admin, web vault, app móvil).
2. Generar **aprendizajes documentados** para más tarde promover a un despliegue de producción (probablemente con dominio propio, Postgres gestionado, backups y SMTP real).

> **No es producción.** Datos pueden borrarse. No usar para credenciales reales.

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

- _(rellenar durante ejecución)_

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
