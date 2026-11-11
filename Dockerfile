# IdeationMax website — static site served by unprivileged nginx
FROM nginxinc/nginx-unprivileged:1.27-alpine

LABEL org.opencontainers.image.title="ideationmax-web" \
      org.opencontainers.image.description="IdeationMax AI & Cloud Consulting website" \
      org.opencontainers.image.url="https://ideationmax.com"

# Replace the default server config
COPY --chown=nginx:nginx nginx/default.conf /etc/nginx/conf.d/default.conf

# Site content
COPY --chown=nginx:nginx site/ /usr/share/nginx/html/

USER nginx
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1
