# STAGE 1 - BUILD
# Instala dependencias Node y compila el proyecto Vite/React
FROM node:20-alpine AS builder
WORKDIR /app

# Copiar package.json y lockfile primero → cachea node_modules por separado.
# Solo se reinstalan dependencias si cambia package.json (no el código fuente).
COPY package.json package-lock.json ./
RUN npm ci --frozen-lockfile

# Copiar el resto del código fuente
COPY . .

# Variable de entorno para la URL base de la API en producción
ARG VITE_API_BASE_URL=""
ENV VITE_API_BASE_URL=${VITE_API_BASE_URL}

# Compilar para producción (genera /app/dist)
RUN npm run build

# STAGE 2 - RUNTIME
# Nginx Alpine sirve los archivos estáticos compilados por Vite
FROM nginx:1.27-alpine
LABEL maintainer="innovatech-chile"
LABEL app="front-despacho"
LABEL version="1.0"

# Instalar gettext para envsubst (reemplazo de variables en nginx.conf)
RUN apk add --no-cache gettext

# Eliminar configuración por defecto de Nginx
RUN rm /etc/nginx/conf.d/default.conf

# Copiar nuestra configuración con variables de entorno (se procesa en entrypoint)
COPY nginx.conf /etc/nginx/templates/app.conf.template

# Copiar los archivos compilados por Vite
COPY --from=builder /app/dist /usr/share/nginx/html

# Ajustar permisos (nginx worker corre como nobody por defecto en alpine)
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    touch /var/run/nginx.pid && \
    chown nginx:nginx /var/run/nginx.pid

# Puerto 80: único puerto expuesto a Internet
EXPOSE 80

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:80 || exit 1

# envsubst procesa las variables en el template antes de iniciar nginx
# Variables con defaults: funciona en local (nombres de contenedor) y en EC2 (IPs)
CMD ["/bin/sh", "-c", \
  "envsubst '${BACK_VENTAS_HOST}${BACK_VENTAS_PORT}${BACK_DESPACHOS_HOST}${BACK_DESPACHOS_PORT}' \
  < /etc/nginx/templates/app.conf.template \
  > /etc/nginx/conf.d/app.conf && \
  nginx -g 'daemon off;'"]
