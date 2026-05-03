# syntax=docker/dockerfile:1.6

# ──────────────────────────────────────────────────────────────────────────────
# gpx.studio — multi-stage build
#
# Stage 1: build the local "gpx" library (TypeScript → dist/)
# Stage 2: build the SvelteKit website as a static site
# Stage 3: serve the static output via nginx:alpine
# ──────────────────────────────────────────────────────────────────────────────

ARG NODE_VERSION=24
ARG NGINX_VERSION=1.27-alpine

# ── Stage 1: build the gpx library ───────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS gpx-builder
WORKDIR /app/gpx

# Install only what's needed to build the lib first (better cache hit-rate)
COPY gpx/package.json gpx/package-lock.json ./
# postinstall already runs `tsc`, but we run build explicitly to be safe
RUN npm ci

COPY gpx/ ./
RUN npm run build


# ── Stage 2: build the website ───────────────────────────────────────────────
FROM node:${NODE_VERSION}-alpine AS website-builder
WORKDIR /app

# The website's package.json references "gpx": "file:../gpx"
# so we need to keep the same relative layout inside the image.
COPY --from=gpx-builder /app/gpx /app/gpx

WORKDIR /app/website
COPY website/package.json website/package-lock.json ./
RUN npm ci

COPY website/ ./

# MapTiler key is a PUBLIC_ key (gets baked into the client bundle by SvelteKit).
# Pass it in via build arg → docker-compose sets it from env / Portainer Stack vars.
ARG PUBLIC_MAPTILER_KEY
ARG BASE_PATH=""
ENV BASE_PATH=${BASE_PATH}

RUN echo "PUBLIC_MAPTILER_KEY=${PUBLIC_MAPTILER_KEY}" > .env \
 && npm run build


# ── Stage 3: serve the static build with nginx ───────────────────────────────
FROM nginx:${NGINX_VERSION} AS runtime

# Replace default config with our SPA-friendly one
COPY deploy/nginx.conf /etc/nginx/conf.d/default.conf

# Copy the prerendered/static build output
COPY --from=website-builder /app/website/build /usr/share/nginx/html

EXPOSE 80

# nginx:alpine's default CMD already runs nginx in the foreground.
# Healthcheck so Portainer shows green when the site is actually serving.
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1/ >/dev/null 2>&1 || exit 1
