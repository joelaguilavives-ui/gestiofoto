-- =============================================================================
-- 0002_clientes_tarifa_pedidos.sql — Fase 2: clientes, tarifa, pedidos y cobros
--
-- Reglas del apartado 4 del PDF que se garantizan aquí (además de en Domain):
--   4.1 código de pedido sin repeticiones (contador en transacción)
--   4.2 precio de tarifa vigente en la fecha del pedido; si se cambia → «manual»
--   4.3 solo combinaciones producto × tamaño con precio
--   4.4 importe de línea redondeado a 2 decimales; total = suma de líneas
--   4.5 los pedidos no se borran: se anulan con motivo
--   4.6 cada cambio de estado queda registrado
--   Clientes 3: un cliente con pedidos no se borra (no hay DELETE para la app)
-- Las tablas de caja (fase 3) crearán el movimiento de caja de cada cobro.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Clientes y eventos
-- -----------------------------------------------------------------------------

-- El código de cliente nuevo sale de una secuencia, no de «recuento + 1».
-- La migración del Excel conserva los IDs actuales y coloca la secuencia detrás
-- del último.
CREATE SEQUENCE cliente_codigo_seq AS integer START 1;

CREATE TABLE cliente (
  id           bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo       integer NOT NULL DEFAULT nextval('cliente_codigo_seq')
                       CONSTRAINT cliente_codigo_uq UNIQUE CHECK (codigo > 0),
  nombre       text    NOT NULL CHECK (btrim(nombre) <> ''),
  direccion    text,
  cp           text    CHECK (cp ~ '^[0-9]{5}$'),
  poblacion    text,
  provincia    text,
  nif          text    CHECK (nif ~ '^[0-9A-Z]{5,12}$'),
  telefono1    text    CHECK (telefono1 ~ '^\+?[0-9]{6,15}$'),  -- solo cifras
  telefono2    text    CHECK (telefono2 ~ '^\+?[0-9]{6,15}$'),
  email        text    CHECK (email ~ '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  notas        text,
  fecha_alta   date    NOT NULL DEFAULT hoy(),
  activo       boolean NOT NULL DEFAULT true,
  fusionado_en bigint  REFERENCES cliente (id),   -- ficha que absorbió a esta
  CONSTRAINT cliente_fusion_ck
    CHECK (fusionado_en IS NULL OR (NOT activo AND fusionado_en <> id))
);
ALTER SEQUENCE cliente_codigo_seq OWNED BY cliente.codigo;
SELECT preparar_tabla('cliente');

CREATE INDEX cliente_nombre_trgm_ix ON cliente USING gin (normalizar_texto(nombre) gin_trgm_ops);
CREATE INDEX cliente_telefono1_ix   ON cliente (telefono1);
CREATE INDEX cliente_telefono2_ix   ON cliente (telefono2);
CREATE INDEX cliente_email_ix       ON cliente (lower(email));

CREATE TABLE evento (
  id                    bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  cliente_id            bigint NOT NULL REFERENCES cliente (id),
  tipo                  text   NOT NULL
                               CHECK (tipo IN ('comunion', 'boda', 'bautizo', 'quinta', 'otro')),
  fecha                 date,
  lugar                 text,
  padres_o_responsables text,
  notas                 text,
  -- permite que pedido exija que su evento sea del mismo cliente
  CONSTRAINT evento_id_cliente_uq UNIQUE (id, cliente_id)
);
SELECT preparar_tabla('evento');
CREATE INDEX evento_cliente_ix ON evento (cliente_id);
CREATE INDEX evento_fecha_ix   ON evento (fecha);

-- Posibles duplicados al dar de alta: mismo teléfono, mismo email o nombre
-- parecido (sin acentos, similitud de trigramas ≥ 0,3).
CREATE FUNCTION buscar_clientes_parecidos(
  p_nombre   text,
  p_telefono text DEFAULT NULL,
  p_email    text DEFAULT NULL,
  p_excluir  bigint DEFAULT NULL)
RETURNS TABLE (cliente_id bigint, codigo integer, nombre text, telefono1 text,
               email text, motivo text, similitud real)
LANGUAGE sql STABLE
AS $$
  SELECT s.id, s.codigo, s.nombre, s.telefono1, s.email, s.motivo_, s.similitud_
    FROM (SELECT c.id, c.codigo, c.nombre, c.telefono1, c.email,
                 CASE
                   WHEN p_telefono IS NOT NULL AND p_telefono IN (c.telefono1, c.telefono2) THEN 'telefono'
                   WHEN p_email IS NOT NULL AND lower(c.email) = lower(p_email)            THEN 'email'
                   ELSE 'nombre'
                 END AS motivo_,
                 similarity(normalizar_texto(c.nombre), normalizar_texto(p_nombre)) AS similitud_
            FROM cliente c
           WHERE c.fusionado_en IS NULL
             AND c.id IS DISTINCT FROM p_excluir
             AND (   (p_telefono IS NOT NULL AND p_telefono IN (c.telefono1, c.telefono2))
                  OR (p_email IS NOT NULL AND lower(c.email) = lower(p_email))
                  OR normalizar_texto(c.nombre) % normalizar_texto(p_nombre))) s
   ORDER BY (s.motivo_ <> 'nombre') DESC, s.similitud_ DESC
   LIMIT 20
$$;

-- -----------------------------------------------------------------------------
-- Catálogo
-- -----------------------------------------------------------------------------

CREATE TABLE producto (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre    text    NOT NULL CHECK (btrim(nombre) <> ''),
  categoria text    NOT NULL CHECK (btrim(categoria) <> ''),  -- fotos, foam, álbum, tablero…
  activo    boolean NOT NULL DEFAULT true,
  orden     integer NOT NULL DEFAULT 0
);
SELECT preparar_tabla('producto');
CREATE UNIQUE INDEX producto_nombre_uq ON producto (normalizar_texto(nombre));

CREATE TABLE tamano (
  id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre text    NOT NULL CHECK (btrim(nombre) <> ''),        -- 10x15, 30x30 – 20 hojas…
  activo boolean NOT NULL DEFAULT true,
  orden  integer NOT NULL DEFAULT 0
);
SELECT preparar_tabla('tamano');
CREATE UNIQUE INDEX tamano_nombre_uq ON tamano (normalizar_texto(nombre));

-- Histórico de precios. Para cambiar un precio se añade una fila con nueva
-- fecha; para retirar una combinación, una fila con disponible = false.
CREATE TABLE precio (
  id            bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  producto_id   bigint        NOT NULL REFERENCES producto (id),
  tamano_id     bigint        NOT NULL REFERENCES tamano (id),
  vigente_desde date          NOT NULL,
  disponible    boolean       NOT NULL DEFAULT true,
  importe       numeric(12,2) CHECK (importe >= 0),           -- IVA incluido
  CONSTRAINT precio_vigencia_uq UNIQUE (producto_id, tamano_id, vigente_desde),
  CONSTRAINT precio_importe_ck  CHECK (disponible = (importe IS NOT NULL))
);
SELECT preparar_tabla('precio');

-- Precio de una combinación en una fecha (NULL si no tiene o está retirada).
CREATE FUNCTION precio_vigente(p_producto bigint, p_tamano bigint, p_fecha date)
RETURNS numeric(12,2)
LANGUAGE sql STABLE
AS $$
  SELECT importe FROM precio
   WHERE producto_id = p_producto AND tamano_id = p_tamano AND vigente_desde <= p_fecha
   ORDER BY vigente_desde DESC
   LIMIT 1
$$;

-- Tarifa completa en una fecha: solo combinaciones con precio.
CREATE FUNCTION tarifa_en(p_fecha date)
RETURNS TABLE (producto_id bigint, tamano_id bigint, importe numeric(12,2), vigente_desde date)
LANGUAGE sql STABLE
AS $$
  SELECT t.producto_id, t.tamano_id, t.importe, t.vigente_desde
    FROM (SELECT DISTINCT ON (p.producto_id, p.tamano_id)
                 p.producto_id, p.tamano_id, p.importe, p.vigente_desde, p.disponible
            FROM precio p
           WHERE p.vigente_desde <= p_fecha
           ORDER BY p.producto_id, p.tamano_id, p.vigente_desde DESC) t
   WHERE t.disponible
$$;

CREATE VIEW tarifa_actual AS SELECT * FROM tarifa_en(hoy());

-- Las «REF» del Excel.
CREATE TABLE tipo_trabajo (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo_antiguo integer CONSTRAINT tipo_trabajo_codigo_antiguo_uq UNIQUE,
  nombre         text         NOT NULL CHECK (btrim(nombre) <> ''),
  iva_pct        numeric(5,2) NOT NULL DEFAULT 21 CHECK (iva_pct BETWEEN 0 AND 100),
  activo         boolean      NOT NULL DEFAULT true,
  orden          integer      NOT NULL DEFAULT 0
);
SELECT preparar_tabla('tipo_trabajo');
CREATE UNIQUE INDEX tipo_trabajo_nombre_uq ON tipo_trabajo (normalizar_texto(nombre));

-- `tipo` decide el comportamiento: efectivo y bizum van a la caja del día
-- (por separado); transferencia queda pendiente de conciliar con el banco.
CREATE TABLE forma_pago (
  id             bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo_antiguo integer CONSTRAINT forma_pago_codigo_antiguo_uq UNIQUE,
  nombre         text    NOT NULL CHECK (btrim(nombre) <> ''),
  tipo           text    NOT NULL CHECK (tipo IN ('efectivo', 'bizum', 'transferencia')),
  activo         boolean NOT NULL DEFAULT true,
  orden          integer NOT NULL DEFAULT 0
);
SELECT preparar_tabla('forma_pago');
CREATE UNIQUE INDEX forma_pago_nombre_uq ON forma_pago (normalizar_texto(nombre));

-- -----------------------------------------------------------------------------
-- Pedidos
-- -----------------------------------------------------------------------------

-- Regla 4.1: AA + P + NNNN + -C + código cliente + - + nombre (hasta 31 car.).
-- Se quitan del nombre los caracteres que no valen en un nombre de carpeta.
CREATE FUNCTION formatear_codigo_pedido(p_anio integer, p_numero integer,
                                        p_cliente_codigo integer, p_nombre text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT lpad((p_anio % 100)::text, 2, '0') || 'P' || lpad(p_numero::text, 4, '0')
         || '-C' || p_cliente_codigo::text
         || '-' || btrim(left(btrim(regexp_replace(p_nombre, '[/:\\]+', ' ', 'g')), 31))
$$;

CREATE TABLE pedido (
  id                       bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  codigo                   text    CONSTRAINT pedido_codigo_uq UNIQUE,
  anio                     integer,
  numero                   integer CHECK (numero BETWEEN 1 AND 9999),
  cliente_id               bigint  NOT NULL REFERENCES cliente (id),
  fecha                    date    NOT NULL DEFAULT hoy(),
  tipo_trabajo_id          bigint  NOT NULL REFERENCES tipo_trabajo (id),
  evento_id                bigint,
  estado                   text    NOT NULL DEFAULT 'encargado'
                                   CHECK (estado IN ('presupuesto', 'encargado', 'enviado',
                                                     'recibido', 'listo', 'avisado',
                                                     'entregado', 'anulado')),
  es_presupuesto           boolean NOT NULL DEFAULT false,
  presupuesto_valido_hasta date,
  carpeta                  text,                    -- ruta de la carpeta del trabajo
  fecha_prevista           date,
  notas                    text,
  motivo_anulacion         text,
  CONSTRAINT pedido_anio_numero_uq UNIQUE (anio, numero),
  -- el evento, si hay, es del mismo cliente; al fusionar clientes se arrastra
  CONSTRAINT pedido_evento_fk FOREIGN KEY (evento_id, cliente_id)
    REFERENCES evento (id, cliente_id) ON UPDATE CASCADE,
  -- un presupuesto no tiene número; un pedido sí
  CONSTRAINT pedido_numeracion_ck CHECK (
       (es_presupuesto     AND anio IS NULL     AND numero IS NULL     AND codigo IS NULL)
    OR (NOT es_presupuesto AND anio IS NOT NULL AND numero IS NOT NULL AND codigo IS NOT NULL)),
  CONSTRAINT pedido_anio_fecha_ck CHECK (anio IS NULL OR anio = EXTRACT(YEAR FROM fecha)::integer),
  CONSTRAINT pedido_estado_ck CHECK (
       (es_presupuesto     AND estado IN ('presupuesto', 'anulado'))
    OR (NOT es_presupuesto AND estado <> 'presupuesto')),
  CONSTRAINT pedido_anulacion_ck CHECK (
    (estado = 'anulado') = (motivo_anulacion IS NOT NULL AND btrim(motivo_anulacion) <> ''))
);
SELECT preparar_tabla('pedido');

CREATE INDEX pedido_cliente_ix      ON pedido (cliente_id);
CREATE INDEX pedido_fecha_ix        ON pedido (fecha);
CREATE INDEX pedido_evento_ix       ON pedido (evento_id);
CREATE INDEX pedido_estado_ix       ON pedido (estado) WHERE estado NOT IN ('entregado', 'anulado');
CREATE INDEX pedido_codigo_trgm_ix  ON pedido USING gin (codigo gin_trgm_ops);

-- Numeración y reglas de estado.
--  * Alta de pedido o conversión de presupuesto → recibe número del contador.
--  * Un pedido numerado conserva número y código para siempre.
--  * Un pedido no vuelve a presupuesto; un anulado no se reactiva.
CREATE FUNCTION trg_pedido_antes() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_cli_codigo integer;
  v_cli_nombre text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF OLD.estado = 'anulado' AND NEW.estado <> 'anulado' THEN
      RAISE EXCEPTION 'El pedido % está anulado y no se puede reactivar', OLD.id;
    END IF;
    IF NOT OLD.es_presupuesto THEN
      IF NEW.es_presupuesto THEN
        RAISE EXCEPTION 'Un pedido no puede volver a ser presupuesto';
      END IF;
      NEW.anio   := OLD.anio;
      NEW.numero := OLD.numero;
      NEW.codigo := OLD.codigo;
      RETURN NEW;
    END IF;
  END IF;

  IF NEW.es_presupuesto THEN
    RETURN NEW;
  END IF;

  -- alta de pedido, o presupuesto que se convierte en pedido
  SELECT codigo, nombre INTO v_cli_codigo, v_cli_nombre FROM cliente WHERE id = NEW.cliente_id;
  NEW.anio   := EXTRACT(YEAR FROM NEW.fecha)::integer;
  NEW.numero := siguiente_numero('P', NEW.anio);
  NEW.codigo := formatear_codigo_pedido(NEW.anio, NEW.numero, v_cli_codigo, v_cli_nombre);
  RETURN NEW;
END $$;
CREATE TRIGGER t10_pedido BEFORE INSERT OR UPDATE ON pedido
  FOR EACH ROW EXECUTE FUNCTION trg_pedido_antes();

-- Historial de estados (laboratorio). Lo escribe solo el trigger de pedido.
-- Fecha = creado_en; usuario = creado_por.
CREATE TABLE pedido_estado_log (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id       bigint NOT NULL REFERENCES pedido (id),
  estado_anterior text,
  estado_nuevo    text   NOT NULL,
  origen          text   NOT NULL CHECK (origen IN ('usuario', 'finder', 'sistema'))
);
SELECT preparar_tabla('pedido_estado_log', p_auditar => false);
CREATE INDEX pedido_estado_log_pedido_ix ON pedido_estado_log (pedido_id, creado_en);

-- Origen del cambio: la app pone set_config('app.origen', 'finder', true) cuando
-- el cambio viene de una etiqueta del Finder. Por defecto, 'usuario'.
CREATE FUNCTION trg_pedido_estado_log() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_anterior text;
BEGIN
  IF TG_OP = 'UPDATE' THEN
    IF NEW.estado IS NOT DISTINCT FROM OLD.estado THEN
      RETURN NULL;
    END IF;
    v_anterior := OLD.estado;
  END IF;
  INSERT INTO pedido_estado_log (pedido_id, estado_anterior, estado_nuevo, origen)
  VALUES (NEW.id, v_anterior, NEW.estado,
          COALESCE(NULLIF(current_setting('app.origen', true), ''), 'usuario'));
  RETURN NULL;
END $$;
CREATE TRIGGER t20_pedido_estado_log AFTER INSERT OR UPDATE OF estado ON pedido
  FOR EACH ROW EXECUTE FUNCTION trg_pedido_estado_log();

-- Líneas sin límite. origen: 'tarifa' (precio de tarifa), 'manual' (producto de
-- tarifa con precio cambiado a mano), 'libre' (descripción y precio a mano).
CREATE TABLE pedido_linea (
  id              bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id       bigint        NOT NULL REFERENCES pedido (id),
  orden           integer       NOT NULL CHECK (orden > 0),
  origen          text          NOT NULL CHECK (origen IN ('tarifa', 'manual', 'libre')),
  producto_id     bigint        REFERENCES producto (id),
  tamano_id       bigint        REFERENCES tamano (id),
  descripcion     text,
  cantidad        numeric(10,2) NOT NULL CHECK (cantidad > 0),
  precio_unitario numeric(12,2) NOT NULL CHECK (precio_unitario >= 0),
  descuento_pct   numeric(5,2)  NOT NULL DEFAULT 0 CHECK (descuento_pct BETWEEN 0 AND 100),
  -- regla 4.4 + IVA 3: redondeo a 2 decimales en cada línea
  importe_bruto   numeric(12,2) GENERATED ALWAYS AS
                    (round(cantidad * precio_unitario, 2)) STORED,
  importe         numeric(12,2) GENERATED ALWAYS AS
                    (round(cantidad * precio_unitario * (1 - descuento_pct / 100), 2)) STORED,
  anadida_en      timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT pedido_linea_orden_uq UNIQUE (pedido_id, orden) DEFERRABLE INITIALLY DEFERRED,
  CONSTRAINT pedido_linea_origen_ck CHECK (
       (origen = 'libre'  AND producto_id IS NULL     AND tamano_id IS NULL
                          AND descripcion IS NOT NULL AND btrim(descripcion) <> '')
    OR (origen <> 'libre' AND producto_id IS NOT NULL AND tamano_id IS NOT NULL))
);
SELECT preparar_tabla('pedido_linea');

-- Reglas 4.2 y 4.3, y no tocar líneas de pedidos anulados.
CREATE FUNCTION trg_pedido_linea_antes() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_pedido_id bigint;
  v_estado    text;
  v_fecha     date;
  v_tarifa    numeric(12,2);
BEGIN
  IF TG_OP = 'DELETE' THEN v_pedido_id := OLD.pedido_id; ELSE v_pedido_id := NEW.pedido_id; END IF;
  SELECT estado, fecha INTO v_estado, v_fecha FROM pedido WHERE id = v_pedido_id;
  IF v_estado = 'anulado' THEN
    RAISE EXCEPTION 'El pedido % está anulado: sus líneas no se pueden cambiar', v_pedido_id;
  END IF;
  IF TG_OP = 'UPDATE' AND NEW.pedido_id <> OLD.pedido_id THEN
    RAISE EXCEPTION 'Una línea no se puede mover a otro pedido';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;

  IF NEW.origen <> 'libre' THEN
    v_tarifa := precio_vigente(NEW.producto_id, NEW.tamano_id, v_fecha);
    IF v_tarifa IS NULL THEN
      RAISE EXCEPTION 'La combinación producto % × tamaño % no tiene precio el %',
        NEW.producto_id, NEW.tamano_id, v_fecha USING ERRCODE = 'check_violation';
    END IF;
    NEW.origen := CASE WHEN NEW.precio_unitario = v_tarifa THEN 'tarifa' ELSE 'manual' END;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t10_pedido_linea BEFORE INSERT OR UPDATE OR DELETE ON pedido_linea
  FOR EACH ROW EXECUTE FUNCTION trg_pedido_linea_antes();

-- -----------------------------------------------------------------------------
-- Cobros y ajustes
-- -----------------------------------------------------------------------------

-- Sin límite de cobros por pedido. Una corrección es un cobro nuevo (puede ser
-- negativo) que apunta al original; el original no se toca.
CREATE TABLE cobro (
  id               bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id        bigint        REFERENCES pedido (id),
  fecha            date          NOT NULL DEFAULT hoy(),
  importe          numeric(12,2) NOT NULL CHECK (importe <> 0),
  forma_pago_id    bigint        NOT NULL REFERENCES forma_pago (id),
  nota             text,
  corrige_cobro_id bigint        REFERENCES cobro (id),
  CONSTRAINT cobro_negativo_ck CHECK (importe > 0 OR corrige_cobro_id IS NOT NULL),
  CONSTRAINT cobro_correccion_ck CHECK (corrige_cobro_id IS DISTINCT FROM id)
);
SELECT preparar_tabla('cobro');
CREATE INDEX cobro_pedido_ix ON cobro (pedido_id);
CREATE INDEX cobro_fecha_ix  ON cobro (fecha);

-- No se cobra un presupuesto ni un pedido anulado (las correcciones sí se admiten).
CREATE FUNCTION trg_cobro_antes() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_pedido pedido%ROWTYPE;
BEGIN
  IF NEW.pedido_id IS NOT NULL AND NEW.corrige_cobro_id IS NULL THEN
    SELECT * INTO v_pedido FROM pedido WHERE id = NEW.pedido_id;
    IF v_pedido.es_presupuesto THEN
      RAISE EXCEPTION 'Un presupuesto no admite cobros: conviértelo antes en pedido';
    END IF;
    IF v_pedido.estado = 'anulado' THEN
      RAISE EXCEPTION 'El pedido % está anulado: no admite cobros', v_pedido.codigo;
    END IF;
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t10_cobro BEFORE INSERT OR UPDATE ON cobro
  FOR EACH ROW EXECUTE FUNCTION trg_cobro_antes();

-- Sustituye a SOBRANTE y REDONDEO DEBE. Signo: lo que resta del pendiente es
-- positivo. «sobrante» (cobrado de más) es negativo; «condonado», positivo.
-- PENDIENTE DE CONFIRMAR con el titular qué es exactamente SOBRANTE (PDF §11).
CREATE TABLE pedido_ajuste (
  id        bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  pedido_id bigint        NOT NULL REFERENCES pedido (id),
  tipo      text          NOT NULL CHECK (tipo IN ('sobrante', 'redondeo', 'condonado')),
  importe   numeric(12,2) NOT NULL CHECK (importe <> 0),
  fecha     date          NOT NULL DEFAULT hoy(),
  motivo    text,
  CONSTRAINT pedido_ajuste_signo_ck CHECK (
       (tipo = 'sobrante'  AND importe < 0)
    OR (tipo = 'condonado' AND importe > 0)
    OR  tipo = 'redondeo')
);
SELECT preparar_tabla('pedido_ajuste');
CREATE INDEX pedido_ajuste_pedido_ix ON pedido_ajuste (pedido_id);

-- Totales calculados: el total nunca se guarda.
-- pendiente = total − cobros − ajustes (regla 4.4)
CREATE VIEW pedido_resumen AS
SELECT p.id                                   AS pedido_id,
       COALESCE(l.subtotal, 0)                AS subtotal,
       COALESCE(l.subtotal, 0) - COALESCE(l.total, 0) AS total_descuento,
       COALESCE(l.total, 0)                   AS total,
       COALESCE(c.cobrado, 0)                 AS cobrado,
       COALESCE(a.ajustes, 0)                 AS ajustes,
       COALESCE(l.total, 0) - COALESCE(c.cobrado, 0) - COALESCE(a.ajustes, 0) AS pendiente,
       COALESCE(l.lineas, 0)                  AS lineas
  FROM pedido p
  LEFT JOIN (SELECT pedido_id, sum(importe_bruto) AS subtotal, sum(importe) AS total,
                    count(*) AS lineas
               FROM pedido_linea GROUP BY pedido_id) l ON l.pedido_id = p.id
  LEFT JOIN (SELECT pedido_id, sum(importe) AS cobrado
               FROM cobro WHERE pedido_id IS NOT NULL GROUP BY pedido_id) c ON c.pedido_id = p.id
  LEFT JOIN (SELECT pedido_id, sum(importe) AS ajustes
               FROM pedido_ajuste GROUP BY pedido_id) a ON a.pedido_id = p.id;

-- Deuda total por cliente (ficha de cliente). Excluye presupuestos y anulados.
CREATE VIEW cliente_deuda AS
SELECT p.cliente_id, sum(r.pendiente) AS pendiente
  FROM pedido p JOIN pedido_resumen r ON r.pedido_id = p.id
 WHERE NOT p.es_presupuesto AND p.estado <> 'anulado'
 GROUP BY p.cliente_id;

-- -----------------------------------------------------------------------------
-- Fusión de clientes duplicados (Clientes 2)
-- Pedidos y eventos pasan a la ficha que se conserva (los cobros van con su
-- pedido). Los pedidos conservan su código original con el C-código antiguo.
-- -----------------------------------------------------------------------------

CREATE FUNCTION fusionar_clientes(p_conservar bigint, p_absorber bigint) RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  IF p_conservar = p_absorber THEN
    RAISE EXCEPTION 'No se puede fusionar un cliente consigo mismo';
  END IF;
  PERFORM 1 FROM cliente
    WHERE id IN (p_conservar, p_absorber) AND fusionado_en IS NULL
    ORDER BY id FOR UPDATE;
  IF (SELECT count(*) FROM cliente
       WHERE id IN (p_conservar, p_absorber) AND fusionado_en IS NULL) <> 2 THEN
    RAISE EXCEPTION 'Alguno de los clientes no existe o ya está fusionado';
  END IF;

  -- al mover el evento, ON UPDATE CASCADE arrastra sus pedidos
  UPDATE evento SET cliente_id = p_conservar WHERE cliente_id = p_absorber;
  UPDATE pedido SET cliente_id = p_conservar WHERE cliente_id = p_absorber;
  UPDATE cliente SET activo = false, fusionado_en = p_conservar WHERE id = p_absorber;
END $$;

-- -----------------------------------------------------------------------------
-- Permisos del rol de la app
-- -----------------------------------------------------------------------------

GRANT SELECT, INSERT, UPDATE ON cliente, evento, producto, tamano, precio, tipo_trabajo,
                                forma_pago, pedido, pedido_linea, cobro, pedido_ajuste
  TO gestiofoto_app;
-- Solo se borran líneas de un pedido en edición y eventos sin pedidos.
GRANT DELETE ON pedido_linea, evento TO gestiofoto_app;
GRANT SELECT ON pedido_estado_log, pedido_resumen, cliente_deuda, tarifa_actual
  TO gestiofoto_app;
GRANT USAGE ON SEQUENCE cliente_codigo_seq TO gestiofoto_app;
