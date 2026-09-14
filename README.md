# Manual de Arquitectura, Contenedorizacion y Despliegue de Aplicaciones

Este documento proporciona una referencia tecnica y teorica exhaustiva sobre el funcionamiento del proyecto, abarcando desde los conceptos fundamentales de sistemas de contenedores hasta la arquitectura de comunicacion cliente-servidor y el despliegue en entornos de produccion.

---

## Indice de Contenidos

1. Fundamentos Teoricos de Docker
   - 1.1 Que es una Imagen de Docker
   - 1.2 Que es un Contenedor
   - 1.3 Gestion de Almacenamiento: Capa Efimera vs Volumenes (Bind Mounts y Named Volumes)
2. Arquitectura de la Aplicacion y Flujo de Datos
   - 2.1 Definicion de Frontend y Backend
   - 2.2 Analisis del Archivo .env: Casos de Uso y Ausencia en este Proyecto
   - 2.3 Mecanismo de Conexion entre el Frontend y la Base de Datos
3. Construccion de Imagenes con Dockerfile
   - 3.1 Anatomia y Directivas de un Dockerfile
   - 3.2 Dockerfile de Nginx (Entorno de la Clase)
   - 3.3 Dockerfile de PocketBase (Entorno Autocontenido de Produccion)
   - 3.4 Sistema de Capas y Cache de Construccion
4. Orquestacion con Docker Compose
   - 4.1 Principios de Orquestacion Multicontenedor
   - 4.2 Redes Aisladas y Resolucion DNS entre Servicios
   - 4.3 Configuracion para Entorno Local (docker-compose.yml)
   - 4.4 Configuracion para Servidor VPS (docker-compose-server.yml)
   - 4.5 Comandos Esenciales de Gestion
5. Administracion y Funcionamiento de PocketBase
   - 5.1 Motor de Base de Datos Embebido (SQLite)
   - 5.2 Aprovisionamiento del Administrador Inicial
   - 5.3 Modelado de Colecciones y Reglas de Acceso (API Rules)
6. Despliegue en Plataformas PaaS (Fly.io)
   - 6.1 Transicion de Docker Compose a MicroVMs
   - 6.2 Estructura del Archivo fly.toml
   - 6.3 Persistencia de Discos en la Nube
   - 6.4 Enrutamiento de Red y Direcciones IP
7. Matriz Comparativa de Entornos

---

## 1. Fundamentos Teoricos de Docker

### 1.1 Que es una Imagen de Docker

Una imagen de Docker es un paquete ejecutable, autonomo e inmutable que incluye todo lo necesario para ejecutar una aplicacion: codigo fuente, entornos de ejecucion, herramientas de sistema, bibliotecas y configuraciones.

Las imagenes se construyen a partir de capas de solo lectura superpuestas mediante un sistema de archivos de union (Union File System / OverlayFS). Cada instruccion ejecutada en un archivo de construccion genera una nueva capa criptograficamente identificada por su hash SHA-256. Al ser de solo lectura, una misma imagen puede servir de molde base para instanciar decenas de entornos identicos sin modificar los binarios originales.

### 1.2 Que es un Contenedor

Un contenedor es una instancia viva y en ejecucion de una imagen de Docker. A diferencia de una maquina virtual tradicional, un contenedor no emula hardware completo ni ejecuta un kernel de sistema operativo independiente; comparte el kernel del sistema operativo anfitrion (Host OS).

El aislamiento se logra a nivel de kernel mediante dos primitivas fundamentales de Linux:
* Namespaces: Proveen aislamiento visual de recursos. Cada contenedor tiene su propio espacio de nombres para procesos (PID), interfaces de red (NET), montajes de archivos (MNT), comunicacion entre procesos (IPC) y usuarios (USER).
* Control Groups (cgroups): Limitan y monitorean el consumo de recursos de hardware, tales como cuotas de procesamiento (CPU), memoria RAM, entrada/salida de disco (I/O) y ancho de banda de red.

Sobre la pila de capas inmutables de la imagen, Docker añade al contenedor una capa delgada de lectura y escritura (Read/Write Layer). Todas las modificaciones que el proceso realice en tiempo de ejecucion ocurren en esta capa.

### 1.3 Gestion de Almacenamiento: Capa Efimera vs Volumenes

Por diseño, la capa de lectura y escritura de un contenedor es efimera. Si un contenedor se detiene y se elimina (mediante `docker rm` o un nuevo despliegue), todos los datos creados durante su ejecucion se destruyen de forma permanente.

Para persistir informacion critico-transaccional (como bases de datos) se utilizan mecanismos de almacenamiento dedicados:

```
+-------------------------------------------------------------+
|                      Host Fisico / OS                       |
|                                                             |
|   +-----------------------+     +-----------------------+   |
|   |   Ruta del Host       |     | /var/lib/docker/      |   |
|   |   (./public_html)     |     | volumes/pb_data/      |   |
|   +-----------+-----------+     +-----------+-----------+   |
|               |                             |               |
|         (Bind Mount)                 (Named Volume)         |
|               |                             |               |
|   +-----------v-----------+     +-----------v-----------+   |
|   |  Contenedor Nginx     |     | Contenedor PocketBase |   |
|   |  /usr/share/nginx/    |     | /pb/pb_data           |   |
|   |  html                 |     |                       |   |
|   +-----------------------+     +-----------------------+   |
+-------------------------------------------------------------+
```

Existen dos tipos principales de montaje:

#### A. Bind Mounts (Montajes Enlazados)
Vinculan de forma directa un archivo o directorio exacto del sistema anfitrion a una ruta interna del contenedor (ejemplo: `./public_html:/usr/share/nginx/html`).
* Caracteristica: El contenedor ve en tiempo real los cambios que el desarrollador hace en su computadora.
* Uso ideal: Entornos de desarrollo local para evitar reconstruir la imagen cada vez que se modifica un archivo HTML o JavaScript.

#### B. Named Volumes (Volumenes con Nombre)
Son areas de almacenamiento gestionadas completamente por el daemon de Docker dentro del directorio protegido del sistema anfitrion (usualmente `/var/lib/docker/volumes/` en Linux).
* Caracteristica: Estan completamente desvinculados del ciclo de vida del contenedor. Un contenedor puede ser borrado, actualizado o reemplazado por otra version de imagen, y el nuevo contenedor puede volver a montar el mismo volumen sin perder un solo registro.
* Uso ideal: Motores de bases de datos, almacenamiento de certificados y logs criticos de produccion.

---

## 2. Arquitectura de la Aplicacion y Flujo de Datos

### 2.1 Definicion de Frontend y Backend

En la ingenieria de software moderna, la separacion de responsabilidades divide la solucion en dos capas principales:

* Backend: Capa logica del lado del servidor. Se encarga del procesamiento de reglas de negocio, persistencia en bases de datos, validacion criptografica de identidades (autenticacion) y exposicion controlada de datos a traves de endpoints de red (APIs).
* Frontend: Capa de presentacion del lado del cliente. Ejecutada dentro del navegador web mediante tecnologias estandar (HTML para estructura semantica, CSS para estilizacion y JavaScript para dinamismo e interaccion).

#### Coexistencia de Front y Back
En marcos de trabajo con Server-Side Rendering (SSR) como PHP, Django o Astro, el servidor procesa y renderiza el HTML final antes de enviarlo al cliente. En arquitecturas Single Page Application (SPA) o sitios estaticos como este proyecto, el frontend se envia como archivos planos y es el navegador del usuario quien ejecuta la logica de peticion asincrona hacia la API externa.

### 2.2 Analisis del Archivo .env: Casos de Uso y Ausencia en este Proyecto

Un archivo `.env` almacena variables de entorno para parametrizar aplicaciones sin incrustar secretos directamente en el repositorio de control de versiones.

#### Cuando es indispensable un archivo .env
En arquitecturas convencionales (por ejemplo, Node.js con Express, Python con FastAPI, o Java con Spring) donde el backend debe comunicarse a traves de la red con un servidor de base de datos externo (PostgreSQL, MariaDB, MySQL):
```env
DB_HOST=192.168.1.50
DB_PORT=5432
DB_USER=admin_sistema
DB_PASSWORD=clave_encriptada_compleja
JWT_SECRET=token_de_firma_privada
```

#### Por que este proyecto no implementa un archivo .env
1. Base de datos embebida: PocketBase no requiere credenciales de conexion de red. Su motor SQLite se ejecuta en el mismo proceso de la aplicacion y se comunica mediante llamadas de sistema a un archivo local de disco (`/pb/pb_data/data.db`).
2. Parametrizacion por flags CLI: La configuracion de red de PocketBase se define directamente en la linea de comandos de arranque (`--http=0.0.0.0:8080`, `--dir=/pb/pb_data`).
3. Seguridad en el cliente: El codigo de `script.js` corre exclusivamente en el navegador del usuario final. En este entorno, los archivos `.env` no proveen ninguna proteccion criptografica ni de ofuscacion; cualquier variable compilada o inyectada en el frontend puede ser inspeccionada de forma trivial mediante las herramientas de desarrollo del navegador (F12).

### 2.3 Mecanismo de Conexion entre el Frontend y la Base de Datos

Por directrices basicas de seguridad, una base de datos nunca debe aceptar conexiones directas desde un cliente web externo. La exposicion de sockets directos a bases de datos permitiria la ejecucion de consultas arbitrarias y ataques de denegacion de servicio o inyeccion.

PocketBase opera como un servidor intermedio que expone una interfaz REST estructurada:

```
[ Navegador Web ]
       |
       | 1. HTTP GET /api/collections/alumnos/records?perPage=50
       v
[ PocketBase: Router HTTP / Capa de Seguridad ]
       |
       | 2. Evaluacion de Reglas de Acceso (API Rules)
       |    - Verifica si la coleccion permite lectura publica
       v
[ PocketBase: Controlador de Base de Datos ]
       |
       | 3. Query interna SQLite (SELECT id, nombre, created FROM alumnos)
       v
[ Archivo SQLite: /pb/pb_data/data.db ]
       |
       | 4. Retorno de registros crudos
       v
[ PocketBase: Serializador ]
       |
       | 5. Empaquetado en formato JSON estructurado
       v
[ Respuesta HTTP 200 OK hacia el Navegador ]
       |
       | 6. Procesamiento DOM en JavaScript
       v
[ Renderizado de etiquetas <li> en el documento HTML ]
```

El codigo en `script.js` gestiona esta interaccion mediante la API Fetch:
```javascript
async function fetchData(){
    const url = '/api/collections/alumnos/records?perPage=50';

    try {
        const response = await fetch(url);
        if (!response.ok) {
            throw new Error(`Error HTTP de respuesta: ${response.status}`);
        }

        const data = await response.json();
        const lista = document.getElementById('lista-alumnos');

        data.items.forEach(alumno => {
            const li = document.createElement('li');
            li.textContent = alumno.nombre || alumno.Nombre;
            lista.appendChild(li);
        });
    } catch(error) {
        console.error('Fallo en la sincronizacion:', error.message);
    }
}
fetchData();
```

---

## 3. Construccion de Imagenes con Dockerfile

### 3.1 Anatomia y Directivas de un Dockerfile

Un `Dockerfile` es un script declarativo que especifica los pasos secuenciales necesarios para construir una imagen de contenedor. Cada directiva genera una capa en el almacenamiento interno de Docker:

* `FROM`: Define la imagen base sobre la que se construira el entorno. Debe ser la primera instruccion valida del archivo.
* `ARG`: Declara variables disponibles exclusivamente durante la fase de construccion (`docker build`), utiles para parametrizar versiones de software.
* `RUN`: Ejecuta comandos en una capa temporal dentro del contenedor durante la construccion e incorpora los archivos resultantes.
* `ADD`: Copia archivos locales o descarga archivos remotos mediante URLs directas hacia el sistema de archivos del contenedor. Si el archivo es un archivo comprimido reconocido (`.tar`, `.tar.gz`), lo descomprime automaticamente.
* `COPY`: Copia archivos y directorios desde el contexto de construccion local hacia el interior de la imagen. A diferencia de `ADD`, es una operacion puramente de copia sin descompresion ni soporte de URLs remotas.
* `EXPOSE`: Documenta el puerto de red en el que el proceso interno de la imagen escuchara conexiones. No publica el puerto hacia el host por si solo; actua como metadata tecnica.
* `CMD`: Define el comando por defecto y los argumentos que se ejecutaran cuando el contenedor se inicie. Si se pasa un comando alternativo al ejecutar `docker run`, este sobreescribe la instruccion `CMD`.

### 3.2 Dockerfile de Nginx (Entorno de la Clase)

Ubicacion: `despliegue-apliaciones/Clase 2/Mi Landing/Dockerfile`

Este Dockerfile fue diseñado por el docente para empaquetar la landing page estatica en un servidor web industrializado (Nginx):

```dockerfile
# 1. Utiliza Alpine Linux con Nginx precompilado (peso aproximado: ~23 MB)
FROM nginx:alpine

# 2. Copia los archivos estaticos del proyecto al directorio raiz servido por Nginx
COPY ./public_html /usr/share/nginx/html

# 3. Informa que el servidor web atiende solicitudes en el puerto estandar HTTP (80)
EXPOSE 80

# 4. Inicia Nginx indicandole que permanezca en primer plano (daemon off) para que el contenedor no se detenga
CMD ["nginx", "-g", "daemon off;"]
```

### 3.3 Dockerfile de PocketBase (Entorno Autocontenido de Produccion)

Ubicacion: `Dockerfile` (en la raiz del repositorio)

Este Dockerfile resuelve el despliegue moderno unificando el backend y el frontend dentro de un unico contenedor eficiente:

```dockerfile
FROM alpine:latest

# Parametrizacion de la version binaria de PocketBase
ARG PB_VERSION=0.22.21

# Instalacion de utilidades de descompresion y certificados de seguridad TLS
RUN apk add --no-cache unzip ca-certificates

# Descarga directa del binario precompilado de arquitectura amd64
ADD https://github.com/pocketbase/pocketbase/releases/download/v${PB_VERSION}/pocketbase_${PB_VERSION}_linux_amd64.zip /tmp/pb.zip

# Descompresion del ejecutable en el directorio /pb/ y remocion del archivo zip temporal
RUN unzip /tmp/pb.zip -d /pb/ && rm /tmp/pb.zip

# Copia de los recursos estaticos a la carpeta reconocida nativamente por PocketBase (pb_public)
COPY ["despliegue-apliaciones/Clase 2/Mi Landing/public_html", "/pb/pb_public"]

# Apertura del puerto 8080
EXPOSE 8080

# Inicializacion de PocketBase con persistencia de base de datos y servidor de archivos estaticos
CMD ["/pb/pocketbase", "serve", "--http=0.0.0.0:8080", "--dir=/pb/pb_data", "--publicDir=/pb/pb_public"]
```

### 3.4 Sistema de Capas y Cache de Construccion

Docker optimiza el tiempo de compilacion evaluando si una instruccion y sus archivos asociados han cambiado desde la ultima ejecucion. Si no se detectan modificaciones, Docker reutiliza la capa existente almacenada en cache (`Using cache`).

Por este motivo, las instrucciones que cambian con menor frecuencia (como la instalacion de paquetes de sistema `RUN apk add`) deben colocarse al principio del archivo, mientras que aquellas que cambian constantemente (como `COPY ./public_html`) deben ubicarse hacia el final.

---

## 4. Orquestacion con Docker Compose

### 4.1 Principios de Orquestacion Multicontenedor

Docker Compose es una herramienta diseñada para definir, configurar y levantar aplicaciones de multiples contenedores en un solo paso. En lugar de ejecutar multiples comandos complejos `docker run` con decenas de banderas por terminal, toda la topologia de la aplicacion se describe en un archivo estructurado en formato YAML.

### 4.2 Redes Aisladas y Resolucion DNS entre Servicios

Cuando Docker Compose ejecuta un archivo, crea de forma transparente una red puente dedicada (Bridge Network). Todos los servicios declarados dentro de la seccion `services` son conectados a esta red.

El motor de Docker incorpora un servidor DNS interno que permite a los contenedores descubrirse mutuamente utilizando su propio nombre de servicio como nombre de host:
* Si el servicio `web` necesita contactar al backend, no necesita conocer la direccion IP interna (ej. `172.18.0.3`); simplemente realiza peticiones a `http://pb:8090`.

### 4.3 Configuracion para Entorno Local (docker-compose.yml)

Ubicacion: `despliegue-apliaciones/Clase 2/Mi Landing/docker-compose.yml`

```yaml
version: '3.8'

services:
  web:
    image: nginx:alpine
    ports:
      - "8080:80"        # Mapeo: Puerto 8080 del host -> Puerto 80 del contenedor Nginx
    volumes:
      - ./public_html:/usr/share/nginx/html  # Bind mount: Reflejo en tiempo real del codigo local
    depends_on:
      - pb               # Asegura el inicio de PocketBase antes de inicializar Nginx

  pb:
    image: elestio/pocketbase:latest
    ports:
      - "8090:8090"      # Mapeo: Puerto 8090 del host -> Puerto 8090 de PocketBase
    volumes:
      - pocketbase_data:/pb/pb_data          # Named volume para aislar la base de datos

volumes:
  pocketbase_data:       # Declaracion del volumen persistente local
```

### 4.4 Configuracion para Servidor VPS (docker-compose-server.yml)

Ubicacion: `despliegue-apliaciones/Clase 2/Mi Landing/docker-compose-server.yml`

A diferencia del entorno de desarrollo, en un servidor de produccion se elimina el bind mount directo (`./public_html`) para garantizar la inmutabilidad y evitar fallos si se modifican directorios locales del host. Se utiliza la imagen construida mediante el Dockerfile:

```yaml
services:
  web:
    image: landing:v1    # Utiliza la imagen empaquetada previamente
    ports:
      - "8080:80"
  pb:
    image: elestio/pocketbase:latest
    ports:
      - "8090:8090"
    volumes:
      - pocketbase_data:/pb/pb_data

volumes:
  pocketbase_data:
```

### 4.5 Comandos Esenciales de Gestion

Comandos enseñados durante la clase para operar y diagnosticar contenedores:

Levantar todos los servicios en segundo plano (modo detached):
```bash
docker compose up -d
```

Levantar servicios especificando un archivo alternativo (produccion):
```bash
docker compose -f docker-compose-server.yml up -d
```

Construir la imagen de la landing page localmente:
```bash
docker build -t landing:v1 .
```

Listar todos los contenedores creados (activos e inactivos):
```bash
docker ps -a
```

Inspeccionar logs de salida en tiempo real de un servicio especifico:
```bash
docker logs -f milanding-pb-1
```

Detener y destruir los contenedores y redes creados por compose (conservando volumenes):
```bash
docker compose down
```

---

## 5. Administracion y Funcionamiento de PocketBase

### 5.1 Motor de Base de Datos Embebido (SQLite)

PocketBase integra internamente el motor de base de datos SQLite compilado en modo WAL (Write-Ahead Logging). Esto permite concurrencia masiva de lectura y un rendimiento de miles de operaciones por segundo sin requerir la sobrecarga de memoria de un gestor de base de datos tradicional como PostgreSQL o MySQL.

Toda la base de datos, configuraciones, indices y esquemas residen en dos archivos ubicados dentro del directorio de persistencia:
* `/pb/pb_data/data.db`: Almacen de datos transaccionales de las colecciones.
* `/pb/pb_data/auxiliary.db`: Almacen de metadatos del sistema, auditoria y registros de logs.

### 5.2 Aprovisionamiento del Administrador Inicial

Al inicializar PocketBase por primera vez, el sistema no contiene credenciales maestras. Existen dos mecanismos para crear la cuenta de superusuario:

1. A traves de la interfaz visual:
   Al ejecutar el contenedor, se expone la ruta administrativa en `http://localhost:8090/_/` (o la direccion publica correspondiente). La consola mostrara un formulario inicial solicitando un correo electronico y una contraseña de al menos 10 caracteres.
2. A traves de la terminal por comando de consola:
   ```bash
   docker exec -it <id_contenedor> /pb/pocketbase superuser upsert admin@correo.com password1234
   ```

### 5.3 Modelado de Colecciones y Reglas de Acceso (API Rules)

PocketBase organiza la informacion en Colecciones (equivalentes a tablas relacionales):

1. Definicion del Esquema:
   Para este proyecto se genera la coleccion `alumnos` con una columna adicional llamada `nombre` de tipo Plain Text.
2. Politicas de Acceso (API Rules):
   PocketBase implementa seguridad granular a nivel de fila y operacion (List/Search, View, Create, Update, Delete).
   * Por defecto, todas las operaciones estan configuradas con la regla `Superuser Only` (candado cerrado), bloqueando cualquier solicitud que no provenga de un token de administrador.
   * Para permitir que el script del frontend consulte los registros de los alumnos sin obligar al usuario a iniciar sesion, se debe limpiar la regla en **List/Search rule** (dejando el campo vacio). Esto convierte la operacion de lectura en un recurso publico de solo lectura.

---

## 6. Despliegue en Plataformas PaaS (Fly.io)

### 6.1 Transicion de Docker Compose a MicroVMs

Mientras que Docker Compose opera sobre un unico nodo o maquina donde el usuario mantiene acceso root, plataformas como Fly.io operan sobre tecnologia de virtualizacion a nivel de hardware ligero mediante **Firecracker MicroVMs**.

Fly.io no ejecuta comandos `docker-compose`. En su lugar, toma el `Dockerfile` de la raiz del proyecto, compila la imagen en sus constructores remotos y la ejecuta dentro de una micro-maquina virtual aislada con arranque casi instantaneo.

### 6.2 Estructura del Archivo fly.toml

Ubicacion: `fly.toml` (en la raiz del repositorio)

El archivo `fly.toml` define la infraestructura declarativa de la aplicacion:

```toml
app = 'despliegue-de-apps'     # Identificador unico de la aplicacion en el cluster global
primary_region = 'gru'         # Centro de datos asignado (Sao Paulo, Brasil)

[build]                        # Indica que el despliegue se basa en el Dockerfile raiz

[[mounts]]
  source = 'pb_data'           # Nombre logico del volumen de disco reservado
  destination = '/pb/pb_data'  # Punto de montaje dentro del sistema de archivos de la VM

[http_service]
  internal_port = 8080         # Puerto interno donde PocketBase escucha conexiones
  force_https = true           # Terminacion TLS automatica y redireccion forzada a HTTPS
  auto_stop_machines = 'stop'  # Suspende la ejecucion de la maquina si no hay trafico entrante
  auto_start_machines = true   # Reactiva la maquina instantaneamente ante una nueva peticion HTTP
  min_machines_running = 0     # Permite consumo cero de recursos en periodos de inactividad

[[vm]]
  memory = '256mb'             # Asignacion de memoria RAM
  cpu_kind = 'shared'          # CPU compartida
  cpus = 1                     # Nucleos virtuales asignados
```

### 6.3 Persistencia de Discos en la Nube

Para garantizar que los registros ingresados en PocketBase no se pierdan al reiniciar la MicroVM o al compilar una nueva version de codigo, se asocia un volumen de bloque fisico:
```bash
fly volumes create pb_data --region gru --size 1
```
Cuando la maquina virtual se inicializa, el subsistema de Fly.io enlaza el bloque virtual `pb_data` directamente sobre la carpeta `/pb/pb_data`.

> Regla Critica de Concurrencia en SQLite:
> Los motores basados en SQLite no admiten escritura distribuida concurrente entre multiples hosts fisicos a traves de la red. Por esta razon, una aplicacion basada en PocketBase debe configurarse estrictamente con **una sola maquina en ejecucion** (`fly scale count 1`).

### 6.4 Enrutamiento de Red y Direcciones IP

Para que la aplicacion sea accesible publicamente a traves del dominio `https://despliegue-de-apps.fly.dev`, Fly.io implementa una red perimetral Anycast:
* Shared IPv4: Direccion IPv4 compartida entre multiples aplicaciones que utiliza el encabezado HTTP `Host` para dirigir el trafico al contenedor correspondiente.
* Dedicated IPv6: Direccion IPv6 asignada de forma exclusiva a la aplicacion.

Sin la asignacion de estas direcciones, los servidores DNS de Fly (`flydns`) no emitiran registros de resolucion tipo A o AAAA, devolviendo errores de host no encontrado.

---

## 7. Matriz Comparativa de Entornos

| Parametro / Capacidad | Docker Compose Local | Servidor VPS Tradicional | Plataforma en la Nube (Fly.io) |
| :--- | :--- | :--- | :--- |
| **Entorno de Ejecucion** | Docker Desktop (Windows/macOS/Linux) | Servidor dedicado / Instancia EC2 / Droplet | Firecracker MicroVMs en la red de Fly |
| **Orquestador** | Docker Compose Engine | Docker Compose via conexion SSH | Fly Machine Orchestrator |
| **Definicion de Infraestructura** | `docker-compose.yml` | `docker-compose-server.yml` | `fly.toml` + `Dockerfile` |
| **Estrategia del Frontend** | Nginx montado con Bind Mount en vivo | Nginx empaquetado en imagen `landing:v1` | Servido por PocketBase en `pb_public` |
| **Mecanismo de Persistencia** | Named Volume local de Docker | Named Volume en disco del servidor | Bloque NVMe persistente (`[[mounts]]`) |
| **Gestion de Certificados SSL** | No disponible por defecto (HTTP plano) | Manual (Certbot / Let's Encrypt / Proxy inverso) | Totalmente automatizado en borde (HTTPS nativo) |
| **Escalado y Suspension** | Manual via terminal local | Manual o mediante scripts de sistema | Automatico (`auto_stop_machines`) |
| **Punto de Entrada URL** | `http://localhost:8080` | `http://<IP_DEL_VPS>:8080` | `https://despliegue-de-apps.fly.dev` |
