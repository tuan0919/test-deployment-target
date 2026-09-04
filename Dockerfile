FROM nginx:1.27-alpine
COPY index.html /usr/share/nginx/html/index.html
HEALTHCHECK --interval=5s --timeout=3s --retries=5 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
