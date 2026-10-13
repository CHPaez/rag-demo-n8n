# Demo RAG con n8n + PGVector

Demo para **consultar manuales técnicos con lenguaje natural**. Se carga un manual (por ejemplo, la interfaz HL7 de un dispositivo médico), se **vectoriza**, y un agente en n8n responde preguntas como *"¿cómo es la trama que envía el monitor?"* leyendo solo los trozos relevantes.

Se instala con **3 comandos** en cualquier equipo con Docker. Usuario, credenciales y flujos se crean solos.

---

## Inicio rápido

```bash
git clone https://github.com/CHPaez/rag-demo-n8n.git
cd rag-demo-n8n
python3 setup_web.py    # formulario web: configurás, desplegás y probás desde el navegador
                        # (alternativa sin navegador: ./setup.sh, ver "Opción B")
```

### Opción A (recomendada): formulario web

`setup_web.py` levanta un asistente en tu propio equipo (solo Python 3, sin instalar nada) y muestra en la terminal una URL del tipo `http://127.0.0.1:8099/?t=...`. Abrila en el navegador; tiene tres pasos:

1. **Configuración:** la API key de OpenAI (con botón **Validar**, que consulta a OpenAI sin gastar crédito), correo y contraseña del administrador, puerto y zona horaria. Los secretos van enmascarados.
2. **Desplegar:** guarda `.env`, levanta los contenedores y muestra el registro en vivo (la primera vez descarga ~2.5 GB).
3. **Probar:** chequeos automáticos (n8n, login, credenciales, pgvector), botón **Vectorizar manual**, y un buscador que muestra los **4 trozos del manual más cercanos a tu pregunta**, que es justo lo que recibe el agente antes de responder. Incluye enlaces para abrir n8n y el chat con el agente.

Si el servidor es remoto, abrí un túnel y usá la misma URL en tu navegador: `ssh -L 8099:127.0.0.1:8099 usuario@IP_DEL_SERVIDOR`.

> **Seguridad del asistente:** escucha solo en `127.0.0.1`, exige el token de un solo uso de la URL y rechaza peticiones con un `Host` ajeno. Se detiene con `Ctrl+C`. Si el puerto 8099 está ocupado: `WIZARD_PORT=8123 python3 setup_web.py`.

### Opción B: pantalla en la terminal

```bash
./setup.sh
```

`setup.sh` muestra una **pantalla** con todos los datos editables antes de desplegar. Los secretos aparecen enmascarados (`v` los muestra u oculta):

```
  Editable
   1) OpenAI API key        sk-...ab12
   2) Admin email           admin@example.com
   3) Admin password        Dem...f1
   4) Admin name            Demo RAG
   5) n8n port (localhost)  5678
   6) Timezone              America/Bogota

  Generated automatically
   7) Database password     c59...19e1
   8) n8n encryption key    627...2f3a

  [1-8] edit   [v] show/hide secrets   [s] save   [d] save and deploy   [q] quit
```

1. Pulsá **`1`** y pegá tu API key de OpenAI (no se ve mientras escribís).
2. Revisá o cambiá lo demás. La contraseña del administrador se genera sola; con `g` en la opción 3 generás otra.
3. Pulsá **`d`** y confirmá: guarda `.env`, levanta los contenedores (la primera vez descarga ~2.5 GB de imágenes) y avisa cuando n8n está listo.

La contraseña de la base de datos y la clave de cifrado se generan solas y quedan **bloqueadas** una vez desplegado, porque cambiarlas rompería los datos y las credenciales guardadas. Para volver a abrir la pantalla y, por ejemplo, cambiar la API key, ejecutá `./setup.sh` de nuevo. Sin terminal interactiva también sirve `./setup.sh sk-tu-key`, que crea el `.env` sin pantalla, y luego `docker compose up -d`.

Abrí **http://localhost:5678** e ingresá con el correo y la contraseña de la pantalla (también están en `.env`). Ya vas a encontrar:

- La cuenta de administrador creada.
- Las credenciales de **Postgres** y **OpenAI** creadas y asignadas a los nodos (nada en rojo).
- Los dos flujos importados.

**Requisitos:** Docker con Compose, una **API key de OpenAI** con crédito, ~1 GB de RAM libre y `bash` (Linux, macOS o WSL en Windows).

## Usar la demo

1. **Vectorizar el manual:** abrí el flujo `01 - Ingesta de manuales` y presioná **Execute workflow**. Lee la carpeta `manuales/` y guarda los vectores en la tabla `manuales`. También se puede por consola:
   ```bash
   docker compose exec -e N8N_RUNNERS_BROKER_PORT=5690 n8n n8n execute --id=ragIngesta01
   ```
2. **Preguntar:** abrí `02 - Chat con el agente`, presioná **Open chat** y probá:
   - *¿Cómo es la trama ORU^R01 que envía el monitor?*
   - *¿Qué significa el código de error E-214?*
   - *¿Qué puerto usa el HIS por defecto?*
   - *El monitor reintenta una y otra vez, ¿qué reviso?*

El repo incluye `manuales/manual-ejemplo-monitor-m100.md`, un manual **ficticio** de un monitor con interfaz HL7, para probar sin datos reales.

### Usar tus propios manuales

Copiá los archivos (`.pdf`, `.md`, `.txt`) a `manuales/` y volvé a ejecutar la ingesta. **Ojo:** ejecutarla dos veces sobre el mismo archivo **duplica** los vectores. Para empezar de cero:

```bash
docker compose exec db psql -U rag -d rag -c "DROP TABLE manuales;"
```

---

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

## Qué usamos

| Pieza | Para qué sirve | Detalle |
|---|---|---|
| **n8n** `2.42.7` | Orquesta los flujos (ingesta y chat) sin escribir código | Interfaz web en `http://localhost:5678` |
| **PostgreSQL 18 + pgvector** `0.8.x` | Guarda los vectores y busca por cercanía | Imagen `pgvector/pgvector:pg18` |
| **OpenAI `text-embedding-3-small`** | Convierte texto en vectores (1536 dimensiones) | Requiere API key |
| **OpenAI `gpt-4o-mini`** | El modelo que redacta la respuesta | Requiere API key |

Dos contenedores (`db` y `n8n`). Los modelos de OpenAI son llamadas externas.

## Qué se automatiza al arrancar

Un script (`scripts/bootstrap.sh`) corre antes de n8n y, con los valores del `.env`:

| Qué | Cuándo |
|---|---|
| Crea la **cuenta de administrador** (`OWNER_EMAIL` / `OWNER_PASSWORD`) | Primer arranque |
| Crea las **credenciales** de Postgres y OpenAI, con IDs fijos que los flujos ya referencian | **En cada arranque** (así un cambio de API key se aplica) |
| Importa los **dos flujos** | Solo la primera vez, para no pisar cambios hechos en la interfaz |

Si preferís crear tu propia cuenta en la interfaz, dejá `OWNER_PASSWORD` vacío en `.env`.

**Cambiar la API key de OpenAI:** editá `OPENAI_API_KEY` en `.env` y ejecutá `docker compose up -d --force-recreate n8n`.

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

> **Seguridad:** al ser una demo, el `.env` guarda la contraseña del administrador en texto plano. Si la instancia queda en internet, protegé la URL con usuario y contraseña en el proxy y usá una contraseña propia, no la generada.

## Comandos útiles

```bash
docker compose ps                  # estado
docker compose logs -f n8n         # logs (incluye mensajes [bootstrap])
docker compose down                # apagar (conserva los datos)
docker compose down -v             # apagar y BORRAR todo (flujos, credenciales, vectores)
```

---

## Estado de validación

Probado en una **copia limpia del repo, sin nada previo**, con `./setup.sh` y `docker compose up -d`:

- El **formulario web** (`setup_web.py`) pasó 45 pruebas automáticas contra su API, sobre una copia limpia: seguridad (token, `Host` ajeno), validaciones, guardado de `.env` (permisos 600), despliegue, chequeos, vectorización, búsqueda (4 trozos ordenados por cercanía) y redespliegue sin perder los vectores. El JavaScript de la página se validó sintácticamente, pero **la interfaz no se revisó visualmente en un navegador**: si algo se ve raro, avisá.
- La **pantalla de configuración** (`./setup.sh`) se probó de punta a punta: editar la key y el puerto, desplegar, y comprobar que la key llega a la credencial de n8n. También se comprobó que rechaza entradas inválidas y que, sobre un despliegue existente, bloquea la clave de la base y la de cifrado.
- El administrador se crea solo y **el login funciona** con las credenciales generadas.
- Se crean las dos credenciales y los dos flujos, ya enlazados (sin nodos en rojo).
- Con una API key inválida, la ingesta llega hasta OpenAI y este responde `401`: la cadena completa está cableada.
- Con un servidor de embeddings **simulado y compatible con OpenAI**, la ingesta termina en `success`: se guardan **4 trozos de 1536 dimensiones** en pgvector, con su texto y metadatos, y la búsqueda por cercanía devuelve el orden esperado (distancia 0 contra sí mismo).

**No verificado:** una ejecución con una API key real de OpenAI, ni las **respuestas del agente de chat** (el nodo del modelo no se ejecutó). Si al probarlo un parámetro de un nodo difiere, ajustalo en la interfaz: los flujos están hechos para n8n `2.42.7`.

## Notas importantes

- **Confidencialidad:** el texto de los manuales **se envía a OpenAI** para vectorizarlo y para responder. Si el manual es propietario o confidencial, usá antes un modelo local (ver abajo).
- **El mismo modelo de embeddings** tiene que usarse en la ingesta y en el chat. Si cambiás uno, hay que volver a vectorizar todo (las dimensiones no coinciden).
- Los secretos viven en `.env`, que **no se sube a git**. Guardá `N8N_ENCRYPTION_KEY`: sin ella no se pueden descifrar las credenciales guardadas en n8n.
- Cada servicio tiene un tope de memoria en `docker-compose.yml` (`db` 300 MB, `n8n` 700 MB) para que un pico no tumbe el servidor.
- Los flujos están en `workflows/` como JSON: se pueden versionar y revisar como cualquier otro archivo.
- **Si la ingesta por consola falla con "Task Broker's port 5679 is already in use"**, es el puerto interno de n8n: por eso el comando incluye `-e N8N_RUNNERS_BROKER_PORT=5690`.

## Alternativas (si se quiere ir más lejos)

| Necesidad | Opción |
|---|---|
| Que nada salga a internet | **Ollama** con modelos locales de embeddings y chat. Necesita bastante más RAM y, idealmente, GPU. |
| Base vectorial dedicada | **Qdrant**: n8n tiene nodo nativo y sirve para colecciones grandes. |
| Relaciones entre conceptos (equipo → interfaz → mensaje) | **Base de grafos** (por ejemplo FalkorDB): responde mejor preguntas que cruzan varios conceptos. Para un manual, los vectores alcanzan. |

## Estructura del repo

```
.
├── setup_web.py                # asistente web: configurar, desplegar y probar
├── setup.sh                    # alternativa en terminal (pantalla de configuración)
├── docker-compose.yml          # n8n + PostgreSQL con pgvector
├── .env.example                # plantilla de configuración
├── scripts/bootstrap.sh        # crea admin, credenciales e importa flujos al arrancar
├── db/init.sql                 # activa la extensión vector
├── manuales/                   # documentos a vectorizar
│   └── manual-ejemplo-monitor-m100.md
└── workflows/
    ├── 01-ingesta.json         # manual → trozos → vectores → PGVector
    └── 02-chat-agente.json     # pregunta → búsqueda → respuesta
```
