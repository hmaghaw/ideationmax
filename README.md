# IdeationMax website

Redesigned static version of https://ideationmax.com, served by an unprivileged nginx container. No build step, no Node runtime, no third-party requests at page load (fonts are self-hosted).

```
ideationmax/
├── Dockerfile
├── docker-compose.yml
├── nginx/default.conf        # gzip, caching, security headers, /healthz
└── site/
    ├── index.html            # all page content
    ├── 404.html
    ├── robots.txt, sitemap.xml
    └── assets/
        ├── styles.css        # design tokens at the top (:root)
        ├── main.js           # mobile menu, active nav, PolyDial call panel
        ├── favicon.svg, og.png
        └── fonts/            # Schibsted Grotesk + Newsreader (SIL OFL)
```

## Run it

```bash
docker compose up -d --build
# open http://localhost:8080
```

Use another port with `PORT=3000 docker compose up -d --build`.

Without compose:

```bash
docker build -t ideationmax-web .
docker run -d --name ideationmax-web -p 8080:8080 --restart unless-stopped ideationmax-web
```

Health check: `curl http://localhost:8080/healthz` returns `ok`. Docker also runs this every 30s (`docker ps` shows `healthy`).

## Preview without Docker

```bash
cd site && python3 -m http.server 8000
```

## Editing content

All text lives in `site/index.html`, grouped by section (`#about`, `#polydial`, `#experience`, `#projects`, `#publications`, `#contact`). Colours and type sizes are variables at the top of `site/assets/styles.css`. After editing, rebuild: `docker compose up -d --build`.

To show the real book cover instead of the typographic one, put the image in `site/assets/` and replace the `.book-cover` div with an `<img>`.

To add an email address to the contact section, add a `mailto:` button next to the LinkedIn one.

## Deploying on the PolyDial server (host nginx + certbot)

The container listens on `127.0.0.1:8081` only. The server's existing nginx terminates HTTPS and proxies to it, in its own server block, so PolyDial's config is never touched.

```
internet ──443──> host nginx ─┬─ polydial.com    ──> PolyDial (unchanged)
                              └─ ideationmax.com ──> 127.0.0.1:8081 ──> ideationmax-web container
```

### 1. Point DNS at the server

At your domain registrar / DNS provider:

| Type | Name  | Value                    |
|------|-------|--------------------------|
| A    | `@`   | PolyDial server's public IP |
| A    | `www` | PolyDial server's public IP |

Remove any old A, AAAA or CNAME records for `@` and `www` that point at Replit. Then remove the custom domain from your Replit deployment so Replit stops claiming it. If the domain is on Cloudflare, set these records to "DNS only" (grey cloud) until the certificate is issued.

Check propagation from your laptop: `dig +short ideationmax.com` should return the server IP.

### 2. Copy the project to the server and run the setup script

```bash
scp ideationmax.zip ubuntu@<server-ip>:~
ssh ubuntu@<server-ip>
unzip ideationmax.zip && cd ideationmax
sudo ./deploy/setup-host.sh
```

The script:
1. Builds and starts the container on `127.0.0.1:8081` (stops if that port is taken; use `sudo PORT=8082 ./deploy/setup-host.sh`)
2. Installs `deploy/ideationmax.com.conf` into nginx (`sites-available` on Ubuntu/Debian, `conf.d` on Amazon Linux)
3. Runs `nginx -t` before reloading, so a bad config can never take PolyDial down
4. Verifies DNS points at this server, then runs `certbot --nginx` for `ideationmax.com` and `www.ideationmax.com` with an HTTP→HTTPS redirect

Certificate renewal uses the certbot timer you already have for PolyDial.

### Updating the site later

```bash
cd ~/ideationmax   # after copying in the new files
sudo docker compose up -d --build
```

No nginx changes are needed for content updates.

### Optional: HSTS

Once HTTPS has worked for a few days, add this inside the `listen 443` server block certbot created in the ideationmax.com nginx file, then `sudo nginx -t && sudo systemctl reload nginx`:

```
add_header Strict-Transport-Security "max-age=31536000" always;
```

### Troubleshooting

- `curl -I http://127.0.0.1:8081/healthz` on the server tells you whether the container is up.
- `sudo tail -f /var/log/nginx/ideationmax.error.log` for proxy errors.
- certbot fails with a challenge error: DNS isn't pointing at the server yet, or port 80 is closed in the EC2 security group (it's already open if PolyDial's certificate renews).

Social-share images and canonical URLs already use `https://ideationmax.com`, so link previews stop referencing the Replit URL once DNS moves.

## Security defaults

- Runs as non-root (`nginx-unprivileged`), all Linux capabilities dropped, read-only filesystem, `no-new-privileges`
- Content-Security-Policy allows only same-origin scripts, styles, fonts and images
- `X-Frame-Options: DENY`, `nosniff`, strict referrer policy, server version hidden
- HTML is revalidated on every request; CSS/JS cached for a week; fonts for a year
