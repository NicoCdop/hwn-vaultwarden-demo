# Passthrough Dockerfile.
# Railway's railway.json does not support deploying directly from a public
# Docker image, so we wrap the official Vaultwarden image in a minimal
# Dockerfile to make this repo deployable as Infrastructure-as-Code.
#
# For DEMO we track :latest. Before promoting to production, pin this to
# an immutable tag (e.g. vaultwarden/server:1.34.3).
FROM vaultwarden/server:latest
