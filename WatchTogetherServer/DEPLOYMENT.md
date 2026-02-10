# WatchTogetherServer Production Deploy (Traefik)

## 1) Configure environment

Create a production env file:

```sh
cp .env.prod.example .env.prod
```

Required values:

- `DOMAIN`: public DNS name pointing to your VPS.
- `TRAEFIK_ACME_EMAIL`: email for Let's Encrypt notifications.
- `TRAEFIK_ACME_CA_SERVER`: Keep production URL by default. Use staging URL only for testing.

## 2) Start the stack

```sh
docker compose --env-file .env.prod -f docker-compose.prod.yml up -d --build
```

What this does:

- `watchtogether` runs privately on the Docker network.
- `traefik` exposes `80/443`, handles TLS, and auto-requests/renews Let's Encrypt certs.
- WebSocket upgrade is handled by Traefik automatically, so clients use `wss://<DOMAIN>`.

## 3) Validate

```sh
docker compose --env-file .env.prod -f docker-compose.prod.yml logs -f traefik watchtogether
```

Look for successful ACME certificate messages in Traefik logs, then test:

```sh
curl -I https://<DOMAIN>
```

## 4) Optional: validate compose with example env

```sh
docker compose --env-file .env.prod.example -f docker-compose.prod.yml config
```
