# Demo RAG con n8n + PGVector

Demo para **consultar manuales técnicos con lenguaje natural**. Se carga un manual (por ejemplo, la interfaz HL7 de un dispositivo médico), se **vectoriza**, y un agente en n8n responde preguntas como *"¿cómo es la trama que envía el monitor?"* leyendo solo los trozos relevantes.

Se levanta con **un solo comando** en cualquier equipo con Docker.

---

## Qué usamos

| Pieza | Para qué sirve | Detalle |
|---|---|---|
| **n8n** `2.42.7` | Orquesta los flujos (ingesta y chat) sin escribir código | Interfaz web en `http://localhost:5678` |
| **PostgreSQL 18 + pgvector** `0.8.x` | Base de datos que guarda los vectores y busca por cercanía | Imagen `pgvector/pgvector:pg18` |
| **OpenAI `text-embedding-3-small`** | Convierte texto en vectores (1536 dimensiones) | Requiere API key |
| **OpenAI `gpt-4o-mini`** | El modelo que redacta la respuesta | Requiere API key |

Todo corre en dos contenedores (`db` y `n8n`). Los modelos de OpenAI son llamadas externas.

## Cómo funciona

```
 INGESTA (una vez por manual)
 ┌─────────┐   ┌──────────────┐   ┌────────────┐   ┌────────────┐   ┌──────────┐
 │ manual  │──▶│ dividir en   │──▶│ embeddings │──▶│ vectores   │──▶│ PGVector │
 │ (.md/   │   │ trozos de    │   │ (texto →   │   │ + texto    │   │ tabla    │
 │  .pdf)  │   │ ~800 caract. │   │  números)  │   │ original   │   │ manuales │
 └─────────┘   └──────────────┘   └────────────┘   └────────────┘   └──────────┘

 CONSULTA (cada pregunta)
 ┌──────────┐   ┌────────────┐   ┌──────────────┐   ┌──────────┐   ┌───────────┐
 │ pregunta │──▶│ embeddings │──▶│ PGVector:    │──▶│  LLM     │──▶│ respuesta │
 │          │   │ (vector)   │   │ 4 trozos más │   │ responde │   │ con base  │
 └──────────┘   └────────────┘   │ cercanos     │   │ con ellos│   │ en manual │
                                 └──────────────┘   └──────────┘   └───────────┘
```

**La idea clave:** un modelo de *embeddings* convierte un texto en una lista de números que representa su **significado**. Textos con significado parecido quedan "cerca" en ese espacio, aunque no compartan palabras. Por eso la búsqueda encuentra el trozo correcto sin necesitar la palabra exacta. El LLM no lee el manual completo: solo recibe los 4 trozos más cercanos, lo que lo hace **más rápido, barato y preciso**. Esta técnica se llama **RAG** (*Retrieval-Augmented Generation*).

---

## Requisitos

- Docker y Docker Compose (`docker compose version`).
- Una **API key de OpenAI** con crédito.
- ~**1 GB de RAM libre** (n8n usa unos 550 MB, la base de datos unos 100 MB).

## Inicio rápido

```bash
# 1. Clonar
git clone https://github.com/CHPaez/rag-demo-n8n.git
cd rag-demo-n8n

# 2. Crear la configuración y generar claves
cp .env.example .env
sed -i "s/^POSTGRES_PASSWORD=.*/POSTGRES_PASSWORD=$(openssl rand -hex 12)/" .env
sed -i "s/^N8N_ENCRYPTION_KEY=.*/N8N_ENCRYPTION_KEY=$(openssl rand -hex 24)/" .env

# 3. Levantar
docker compose up -d

# 4. Importar los dos flujos
docker compose exec n8n n8n import:workflow --input=/workflows/01-ingesta.json
docker compose exec n8n n8n import:workflow --input=/workflows/02-chat-agente.json
```

Abrí **http://localhost:5678**, creá el usuario administrador y seguí con las credenciales.

### Credenciales (se crean una sola vez en n8n)

En **Credentials → Create**:

1. **Postgres**
   - Host: `db`
   - Database / User: los de tu `.env` (por defecto `rag`)
   - Password: `POSTGRES_PASSWORD` de tu `.env`
   - Port: `5432`
   - SSL: `disable`
2. **OpenAI API**: pegá tu API key.

Después abrí cada flujo y, en los nodos marcados en rojo (PGVector, Embeddings, Modelo de chat), **elegí la credencial** que acabás de crear.

## Usar la demo

1. **Cargar el manual:** abrí el flujo `01 - Ingesta de manuales` y presioná **Execute workflow**. Lee todo lo que haya en la carpeta `manuales/` y lo guarda vectorizado en la tabla `manuales`.
2. **Preguntar:** abrí el flujo `02 - Chat con el agente`, presioná **Open chat** y probá:
   - *¿Cómo es la trama ORU^R01 que envía el monitor?*
   - *¿Qué significa el código de error E-214?*
   - *¿Qué puerto usa el HIS por defecto?*
   - *El monitor reintenta una y otra vez, ¿qué reviso?*

El repo incluye `manuales/manual-ejemplo-monitor-m100.md`, un manual **ficticio** de un monitor con interfaz HL7, para probar sin datos reales.

### Usar tus propios manuales

Copiá los archivos (`.pdf`, `.md`, `.txt`) a la carpeta `manuales/` y volvé a ejecutar el flujo de ingesta. **Ojo:** ejecutarlo dos veces sobre el mismo archivo **duplica** los vectores. Para empezar de cero:

```bash
docker compose exec db psql -U rag -d rag -c "TRUNCATE manuales;"
```

---

## Acceso desde otro equipo (servidor remoto)

n8n escucha **solo en `127.0.0.1`** a propósito: Docker publica puertos saltándose el firewall (`ufw`), así que no queremos exponerlo a internet. Para abrirlo desde tu computador usá un túnel SSH:

```bash
ssh -L 5678:127.0.0.1:5678 usuario@IP_DEL_SERVIDOR
```

Y abrí `http://localhost:5678` en tu navegador.

## Publicarlo en un dominio (opcional)

Para probarlo desde un navegador sin túnel, se puede poner un proxy inverso (nginx, Caddy, etc.) con HTTPS delante de n8n. Creá un archivo `docker-compose.override.yml` junto al `docker-compose.yml` (Docker Compose lo carga solo; el repo ya lo ignora):

```yaml
services:
  n8n:
    environment:
      N8N_HOST: tu-dominio.com
      N8N_PROTOCOL: https
      WEBHOOK_URL: https://tu-dominio.com/
      N8N_PROXY_HOPS: "1"
```

Y en el proxy: reenviá a `127.0.0.1:5678`, activá **WebSockets** (`Upgrade`/`Connection`) y desactivá el buffering para que el chat responda en streaming.

> **Seguridad:** la primera persona que abre n8n crea la cuenta de administrador. Si la instancia queda en internet, protegé la URL con usuario y contraseña en el proxy (o creá tu cuenta de inmediato) antes de compartirla.

## Comandos útiles

```bash
docker compose ps                  # estado
docker compose logs -f n8n         # logs
docker compose down                # apagar (conserva los datos)
docker compose down -v             # apagar y BORRAR todo (flujos, credenciales, vectores)
```

---

## Estado de validación

Verificado al construir el repo:

- `docker compose up -d` levanta ambos servicios y la base queda `healthy`.
- La extensión `vector` (pgvector 0.8.x) queda instalada automáticamente.
- n8n responde en `/healthz`.
- Los dos flujos se **importan sin errores** y n8n conserva tipos de nodo, versiones, parámetros y conexiones.

**No verificado:** una ejecución completa con credenciales reales (se necesita una API key de OpenAI). Si al correrlo algún nodo muestra un parámetro distinto, ajustalo en la interfaz: los flujos están hechos para n8n `2.42.7`.

## Notas importantes

- **Confidencialidad:** con esta configuración el texto de los manuales **se envía a OpenAI** para vectorizarlo y para responder. Si el manual es propietario o confidencial, usá antes un modelo local (ver abajo).
- **El mismo modelo de embeddings** tiene que usarse en la ingesta y en el chat. Si cambiás uno, hay que volver a vectorizar todo (las dimensiones no coinciden).
- Las contraseñas y la `N8N_ENCRYPTION_KEY` viven en `.env`, que **no se sube a git**. Guardá la clave: sin ella no se pueden descifrar las credenciales guardadas en n8n.
- Cada servicio tiene un tope de memoria en `docker-compose.yml` (`db` 300 MB, `n8n` 700 MB) para que un pico no tumbe el servidor.
- Los flujos están en `workflows/` como JSON: se pueden versionar y revisar como cualquier otro archivo.

## Alternativas (si se quiere ir más lejos)

| Necesidad | Opción |
|---|---|
| Que nada salga a internet | **Ollama** con modelos locales de embeddings y chat. Necesita bastante más RAM y, idealmente, GPU. |
| Base vectorial dedicada | **Qdrant**: n8n tiene nodo nativo y sirve para colecciones grandes. |
| Relaciones entre conceptos (equipo → interfaz → mensaje) | **Base de grafos** (por ejemplo FalkorDB): responde mejor preguntas que cruzan varios conceptos. Para un manual, los vectores alcanzan. |

## Estructura del repo

```
.
├── docker-compose.yml          # n8n + PostgreSQL con pgvector
├── .env.example                # plantilla de configuración
├── db/init.sql                 # activa la extensión vector
├── manuales/                   # documentos a vectorizar
│   └── manual-ejemplo-monitor-m100.md
└── workflows/
    ├── 01-ingesta.json         # manual → trozos → vectores → PGVector
    └── 02-chat-agente.json     # pregunta → búsqueda → respuesta
```
