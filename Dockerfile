FROM alpine:latest

# Versión de PocketBase
ARG PB_VERSION=0.22.21

RUN apk add --no-cache unzip ca-certificates

# Descargar y descomprimir PocketBase
ADD https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip /tmp/pb.zip
RUN unzip /tmp/pb.zip -d /pb/ && rm /tmp/pb.zip

# Copiar el frontend estático a la carpeta pb_public de PocketBase
COPY ["despliegue-apliaciones/Clase 2/Mi Landing/public_html", "/pb/pb_public"]

# Exponer el puerto estándar
EXPOSE 8080

# Iniciar PocketBase con datos persistentes en /pb/pb_data y frontend en /pb/pb_public
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8080", "--dir=/pb/pb_data", "--publicDir=/pb/pb_public"]
