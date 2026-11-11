# IdeationMax website

Redesigned static version of https://ideationmax.com, served by an unprivileged nginx container. No build step, no Node runtime, no third-party requests at page load (fonts are self-hosted).

```
ideationmax/
├── .env                      # PORT the site is published on (127.0.0.1:PORT)
├── .env.example              # template for .env
├── docker-compose.yml        # the only way the site is run
├── Dockerfile
├── nginx/default.conf        # container's nginx: gzip, caching, security headers, /healthz
├── deploy/
│   ├── ideationmax.com.conf  # host nginx server block (HTTPS proxy)
│   └── setup-host.sh         # one-time server setup + certificate
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

## Configuration: `.env`

The site runs with Docker Compose, which automatically reads `.env` from the project folder. It has one setting:

```dotenv
PORT=8081
```

`PORT` is the port on `127.0.0.1` that the site is published on. Inside the container nginx always listens on 8080; compose maps `127.0.0.1:PORT` to it. Because it's bound to localhost, the site isn't reachable from outside the server directly, only through the host's nginx.

If `.env` is missing, `docker compose` stops with `required variable PORT is missing a value`. Recreate it with `cp .env.example .env`.

**Changing the port** (for example, if 8081 is taken on the server):

1. Edit `.env`: `PORT=8082`
2. Run `sudo ./deploy/setup-host.sh` again. It recreates the container on the new port and points the host nginx at it.

Running only `docker compose up -d` after changing the port moves the container but leaves nginx pointing at the old port, so the site returns `502 Bad Gateway`.

## Running with Docker Compose

Run these from the `ideationmax` folder (prefix with `sudo` if your user isn't in the `docker` group).

| Task | Command |
|------|---------|
| Build and start (or apply changes) | `docker compose up -d --build` |
| Status and health | `docker compose ps` |
| Follow logs | `docker compose logs -f` |
| Restart | `docker compose restart` |
| Stop and remove the container | `docker compose down` |
| Show the resolved config (checks `.env`) | `docker compose config` |

The container restarts on its own after crashes and server reboots (`restart: unless-stopped`).

Check it's serving, using the port from `.env`:

```bash
curl http://127.0.0.1:8081/healthz      # prints: ok
```

Compose also runs this health check every 30 seconds; `docker compose ps` shows `healthy`.

To try it on your own machine before deploying, run `docker compose up -d --build` and open `http://127.0.0.1:8081`.

## Preview without Docker

```bash
cd site && python3 -m http.server 8000
```

## Editing content

All text lives in `site/index.html`, grouped by section (`#about`, `#polydial`, `#experience`, `#projects`, `#publications`, `#contact`). Colours and type sizes are variables at the top of `site/assets/styles.css`. After editing, rebuild: `docker compose up -d --build`.

To show the real book cover instead of the typographic one, put the image in `site/assets/` and replace the `.book-cover` div with an `<img>`.

To add an email address to the contact section, add a `mailto:` button next to the LinkedIn one.

## Deploying on the PolyDial server (host nginx + certbot)

The container listens on `127.0.0.1:PORT` only (8081 by default, set in `.env`). The server's existing nginx terminates HTTPS and proxies to it, in its own server block, so PolyDial's config is never touched.

```
internet ──443──> host nginx ─┬─ polydial.com    ──> PolyDial (unchanged)
                              └─ ideationmax.com ──> 127.0.0.1:PORT ──> ideationmax-web container
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
cat .env                      # check PORT; change it if that port is in use on the server
sudo ./deploy/setup-host.sh
```

`ls -a` shows `.env`; `unzip` keeps hidden files, but some upload tools skip them. If it's missing, `cp .env.example .env`.

The script:
1. Reads `PORT` from `.env` and runs `docker compose up -d --build` (stops if that port is taken by something else; set another port in `.env` and re-run)
2. Installs `deploy/ideationmax.com.conf` into nginx (`sites-available` on Ubuntu/Debian, `conf.d` on Amazon Linux)
3. Runs `nginx -t` before reloading, so a bad config can never take PolyDial down
4. Verifies DNS points at this server, then runs `certbot --nginx` for `ideationmax.com` and `www.ideationmax.com` with an HTTP→HTTPS redirect

### How the HTTPS certificate is renewed

Nothing extra needs setting up. ideationmax.com renews through the same mechanism that already keeps polydial.com's certificate valid.

**What happens automatically**

1. **A scheduler runs `certbot renew` twice a day.** Which one depends on how certbot was installed:
   - apt/dnf package: a systemd timer, `certbot.timer`, or on older systems a cron job in `/etc/cron.d/certbot`
   - snap: a systemd timer, `snap.certbot.renew.timer`
2. **certbot checks every certificate it manages**, polydial.com and ideationmax.com alike. Each has its own settings file in `/etc/letsencrypt/renewal/`. A certificate that isn't close to expiry is skipped, so most runs do nothing.
3. **When a certificate is due**, certbot proves to Let's Encrypt that it controls the domain. It uses the nginx plugin, which briefly serves a challenge file on port 80. Port 80 must stay open in the EC2 security group, and the HTTP→HTTPS redirect doesn't get in the way.
4. **certbot reloads nginx** so the new certificate is used. This is a graceful reload, so PolyDial and the site container keep running with no downtime.

The site container is never involved: nginx on the host holds the certificate, and traffic to the container stays plain HTTP on localhost.

**Certificate lifetimes are getting shorter.** Let's Encrypt certificates are currently valid for 90 days. They become 64 days from 10 February 2027 and 45 days in 2028. Automatic renewal handles this without changes, but keep certbot updated (`sudo apt upgrade certbot python3-certbot-nginx`, or `sudo snap refresh certbot`). Older versions renew at a fixed 30 days before expiry, which leaves little margin on short certificates.

**Checking that renewal works**

```bash
# Is the scheduler active, and when does it next run?
systemctl list-timers | grep -i certbot        # no output? check: cat /etc/cron.d/certbot

# Which certificates exist and when do they expire?
sudo certbot certificates

# Rehearse a renewal against Let's Encrypt's test servers (changes nothing)
sudo certbot renew --dry-run

# What happened on recent runs?
sudo tail -n 50 /var/log/letsencrypt/letsencrypt.log
```

Run `sudo certbot renew --dry-run` once after the first deploy. If it says both certificates renewed successfully, renewal is working.

**If renewal fails**, Let's Encrypt doesn't email expiry warnings any more, so failures are silent until the site shows a certificate error. Common causes:

- **Port 80 closed** in the security group or a firewall. Reopen it to `0.0.0.0/0`.
- **DNS moved away** from this server, or Cloudflare set to proxied (orange cloud). Point the A records back at the server, or set them to "DNS only".
- **nginx config error** from an unrelated change. Run `sudo nginx -t`, fix the error, then `sudo certbot renew`.

For an early warning, add an external uptime monitor that checks certificate expiry, such as UptimeRobot or Better Stack.

### Updating the site later

```bash
cd ~/ideationmax   # after copying in the new files; keep your existing .env
sudo docker compose up -d --build
```

No nginx changes are needed for content updates. If you unzip a new copy over the old folder, check `.env` still has the port you're using (`cat .env`).

### Optional: HSTS

Once HTTPS has worked for a few days, add this inside the `listen 443` server block certbot created in the ideationmax.com nginx file, then `sudo nginx -t && sudo systemctl reload nginx`:

```
add_header Strict-Transport-Security "max-age=31536000" always;
```

### Troubleshooting

- `sudo docker compose ps` and `curl http://127.0.0.1:<PORT>/healthz` (port from `.env`) tell you whether the container is up.
- `sudo docker compose logs -f` for the container's own logs.
- **502 Bad Gateway**: the container is down, or `.env` and the host nginx disagree on the port. Compare `grep PORT .env` with `grep 127.0.0.1 /etc/nginx/sites-available/ideationmax.com` (or `/etc/nginx/conf.d/ideationmax.com.conf`), then re-run `sudo ./deploy/setup-host.sh`.
- `sudo tail -f /var/log/nginx/ideationmax.error.log` for proxy errors.
- certbot fails with a challenge error: DNS isn't pointing at the server yet, or port 80 is closed in the EC2 security group (it's already open if PolyDial's certificate renews).

Social-share images and canonical URLs already use `https://ideationmax.com`, so link previews stop referencing the Replit URL once DNS moves.

## Security defaults

- Runs as non-root (`nginx-unprivileged`), all Linux capabilities dropped, read-only filesystem, `no-new-privileges`
- Content-Security-Policy allows only same-origin scripts, styles, fonts and images
- `X-Frame-Options: DENY`, `nosniff`, strict referrer policy, server version hidden
- HTML is revalidated on every request; CSS/JS cached for a week; fonts for a year
