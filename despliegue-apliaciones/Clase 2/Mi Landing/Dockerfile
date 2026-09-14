FROM alpine:latest
# Versión de PocketBase a descargar
ARG PB_VERSION=0.22.21
RUN apk add --no-cache unzip ca-certificates
# Descargar y descomprimir PocketBase
ADD https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip /tmp/pb.zip
RUN unzip /tmp/pb.zip -d /pb/ && rm /tmp/pb.zip
# Copiar tu landing page a la carpeta de estáticos de PocketBase
COPY ./public_html /pb/pb_public
# Exponer el puerto estándar
EXPOSE 8080
# Iniciar PocketBase indicando la ruta de datos (/pb/pb_data) y estáticos (/pb/pb_public)
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8080", "--dir=/pb/pb_data", "--publicDir=/pb/pb_public"]