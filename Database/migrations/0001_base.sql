-- =============================================================================
-- 0001_base.sql — Fase 1: base técnica
--
-- Extensiones, utilidades comunes, usuarios y PIN, auditoría, configuración y
-- contador de numeración.
--
-- Requisitos previos (los crea Tools/setup_server, no esta migración):
--   * base de datos `gestiofoto`, propiedad del rol `gestiofoto_owner`
--     (aplica las migraciones; solo lo usa la app del Mac principal);
--   * rol `gestiofoto_app` (LOGIN, sin privilegios de administrador): el que usan
--     las dos apps para trabajar.
--
-- Convenciones de todas las tablas (las añade preparar_tabla()):
--   id (identity) · creado_en · creado_por · actualizado_en · actualizado_por ·
--   version (control de edición simultánea).
-- Cada transacción de la app empieza con
--   SELECT set_config('app.usuario_id', '<id>', true);
-- Sin eso, cualquier alta, cambio o borrado se rechaza.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- hash de PIN
CREATE EXTENSION IF NOT EXISTS pg_trgm;    -- búsqueda aproximada y duplicados
CREATE EXTENSION IF NOT EXISTS unaccent;   -- búsqueda sin acentos

-- Zona horaria de la tienda para todas las sesiones nuevas.
DO $$
BEGIN
  EXECUTE format('ALTER DATABASE %I SET timezone = %L', current_database(), 'Europe/Madrid');
END $$;

-- -----------------------------------------------------------------------------
-- Utilidades
-- -----------------------------------------------------------------------------

-- Fecha de hoy en la tienda, independiente de la zona de la sesión.
CREATE FUNCTION hoy() RETURNS date
LANGUAGE sql STABLE PARALLEL SAFE
AS $$ SELECT (now() AT TIME ZONE 'Europe/Madrid')::date $$;

-- Usuario que firma la transacción en curso.
CREATE FUNCTION app_usuario() RETURNS bigint
LANGUAGE plpgsql STABLE
AS $$
DECLARE
  v text := current_setting('app.usuario_id', true);
BEGIN
  IF v IS NULL OR v = '' THEN
    RAISE EXCEPTION 'Transacción sin usuario: falta set_config(''app.usuario_id'', …, true)'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  RETURN v::bigint;
END $$;

-- Texto normalizado para buscar: minúsculas, sin acentos, espacios simples.
CREATE FUNCTION f_unaccent(text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$;

CREATE FUNCTION normalizar_texto(text) RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE STRICT
AS $$ SELECT lower(public.f_unaccent(btrim(regexp_replace($1, '\s+', ' ', 'g')))) $$;

-- -----------------------------------------------------------------------------
-- Triggers comunes
-- -----------------------------------------------------------------------------

-- Columnas de control: quién y cuándo, y número de versión.
CREATE FUNCTION trg_estandar_antes() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    NEW.creado_en       := now();
    NEW.creado_por      := app_usuario();
    NEW.actualizado_en  := NEW.creado_en;
    NEW.actualizado_por := NEW.creado_por;
    NEW.version         := 1;
  ELSE
    IF NEW.id IS DISTINCT FROM OLD.id THEN
      RAISE EXCEPTION 'El id de % no se puede cambiar', TG_TABLE_NAME;
    END IF;
    NEW.creado_en       := OLD.creado_en;
    NEW.creado_por      := OLD.creado_por;
    NEW.actualizado_en  := now();
    NEW.actualizado_por := app_usuario();
    NEW.version         := OLD.version + 1;
  END IF;
  RETURN NEW;
END $$;

-- Auditoría (se define la tabla más abajo). SECURITY DEFINER: la app no puede
-- escribir en `auditoria` directamente.
CREATE FUNCTION trg_auditoria() RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_antes   jsonb;
  v_despues jsonb;
BEGIN
  IF TG_OP <> 'INSERT' THEN v_antes   := to_jsonb(OLD) - 'pin_hash'; END IF;
  IF TG_OP <> 'DELETE' THEN v_despues := to_jsonb(NEW) - 'pin_hash'; END IF;
  INSERT INTO auditoria (tabla, registro_id, accion, usuario_id, antes, despues)
  VALUES (TG_TABLE_NAME,
          COALESCE(v_despues ->> 'id', v_antes ->> 'id')::bigint,
          TG_OP, app_usuario(), v_antes, v_despues);
  RETURN NULL;
END $$;

-- Aviso al otro Mac (LISTEN gestiofoto_cambios) para refrescar listas.
CREATE FUNCTION trg_notificar() RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
  v_id bigint;
BEGIN
  IF TG_OP = 'DELETE' THEN v_id := OLD.id; ELSE v_id := NEW.id; END IF;
  PERFORM pg_notify('gestiofoto_cambios', json_build_object(
    'tabla',   TG_TABLE_NAME,
    'accion',  TG_OP,
    'id',      v_id,
    'usuario', current_setting('app.usuario_id', true))::text);
  RETURN NULL;
END $$;

-- Añade las columnas de control y los triggers comunes a una tabla.
-- Orden de los BEFORE: t00_ (control) va antes que los t10_… de cada tabla.
CREATE FUNCTION preparar_tabla(p_tabla regclass, p_auditar boolean DEFAULT true)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  EXECUTE format($f$
    ALTER TABLE %s
      ADD COLUMN creado_en       timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN creado_por      bigint      NOT NULL REFERENCES usuario (id),
      ADD COLUMN actualizado_en  timestamptz NOT NULL DEFAULT now(),
      ADD COLUMN actualizado_por bigint      NOT NULL REFERENCES usuario (id),
      ADD COLUMN version         integer     NOT NULL DEFAULT 1 CHECK (version > 0)
  $f$, p_tabla);
  EXECUTE format('CREATE TRIGGER t00_estandar BEFORE INSERT OR UPDATE ON %s
                  FOR EACH ROW EXECUTE FUNCTION trg_estandar_antes()', p_tabla);
  IF p_auditar THEN
    EXECUTE format('CREATE TRIGGER t90_auditoria AFTER INSERT OR UPDATE OR DELETE ON %s
                    FOR EACH ROW EXECUTE FUNCTION trg_auditoria()', p_tabla);
  END IF;
  EXECUTE format('CREATE TRIGGER t91_notificar AFTER INSERT OR UPDATE OR DELETE ON %s
                  FOR EACH ROW EXECUTE FUNCTION trg_notificar()', p_tabla);
END $$;

-- -----------------------------------------------------------------------------
-- usuario
-- -----------------------------------------------------------------------------

CREATE TABLE usuario (
  id                bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  nombre            text    NOT NULL CHECK (btrim(nombre) <> ''),
  pin_hash          text,                         -- bcrypt; la app no puede leerlo
  rol               text    NOT NULL DEFAULT 'titular'
                            CHECK (rol IN ('titular', 'dependiente')),
  activo            boolean NOT NULL DEFAULT true,
  es_sistema        boolean NOT NULL DEFAULT false, -- firma migraciones e importaciones
  intentos_fallidos integer NOT NULL DEFAULT 0 CHECK (intentos_fallidos >= 0),
  bloqueado_hasta   timestamptz,
  ultimo_acceso     timestamptz,
  CONSTRAINT usuario_pin_ck     CHECK (es_sistema OR pin_hash IS NOT NULL),
  CONSTRAINT usuario_sistema_ck CHECK (NOT (es_sistema AND activo))
);
CREATE UNIQUE INDEX usuario_nombre_uq ON usuario (normalizar_texto(nombre));
SELECT preparar_tabla('usuario');

CREATE FUNCTION es_titular(p_usuario_id bigint) RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (SELECT 1 FROM usuario
                 WHERE id = p_usuario_id AND rol = 'titular' AND (activo OR es_sistema))
$$;

CREATE FUNCTION exigir_titular() RETURNS void
LANGUAGE plpgsql STABLE
AS $$
BEGIN
  IF NOT es_titular(app_usuario()) THEN
    RAISE EXCEPTION 'Solo el titular puede hacer esta operación'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END $$;

-- Cambios de nombre, rol o estado de un usuario: solo titular.
CREATE FUNCTION trg_usuario_titular() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  PERFORM exigir_titular();
  IF OLD.es_sistema THEN
    RAISE EXCEPTION 'El usuario Sistema no se puede modificar';
  END IF;
  RETURN NEW;
END $$;
CREATE TRIGGER t10_usuario_titular BEFORE UPDATE OF nombre, rol, activo ON usuario
  FOR EACH ROW EXECUTE FUNCTION trg_usuario_titular();

CREATE FUNCTION validar_formato_pin(p_pin text) RETURNS void
LANGUAGE plpgsql IMMUTABLE
AS $$
BEGIN
  IF p_pin IS NULL OR p_pin !~ '^[0-9]{4,6}$' THEN
    RAISE EXCEPTION 'El PIN debe tener entre 4 y 6 cifras' USING ERRCODE = 'check_violation';
  END IF;
END $$;

-- Alta de usuario (solo titular). Devuelve el id nuevo.
CREATE FUNCTION crear_usuario(p_nombre text, p_rol text, p_pin text) RETURNS bigint
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  v_id bigint;
BEGIN
  PERFORM exigir_titular();
  PERFORM validar_formato_pin(p_pin);
  INSERT INTO usuario (nombre, rol, pin_hash)
  VALUES (btrim(p_nombre), p_rol, crypt(p_pin, gen_salt('bf', 8)))
  RETURNING id INTO v_id;
  RETURN v_id;
END $$;

-- Cambio de PIN: el propio usuario o un titular.
CREATE FUNCTION establecer_pin(p_usuario_id bigint, p_pin text) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
BEGIN
  IF app_usuario() <> p_usuario_id AND NOT es_titular(app_usuario()) THEN
    RAISE EXCEPTION 'Solo el propio usuario o un titular puede cambiar el PIN'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
  PERFORM validar_formato_pin(p_pin);
  UPDATE usuario
     SET pin_hash = crypt(p_pin, gen_salt('bf', 8)),
         intentos_fallidos = 0, bloqueado_hasta = NULL
   WHERE id = p_usuario_id AND NOT es_sistema;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Usuario % no encontrado', p_usuario_id;
  END IF;
END $$;

-- Inicio de sesión. Tras 5 fallos seguidos, bloqueo de 5 minutos.
-- Si el PIN es correcto, la transacción queda firmada por ese usuario.
CREATE FUNCTION verificar_pin(p_usuario_id bigint, p_pin text) RETURNS boolean
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
DECLARE
  u    usuario%ROWTYPE;
  v_ok boolean;
BEGIN
  SELECT * INTO u FROM usuario
   WHERE id = p_usuario_id AND activo AND NOT es_sistema
   FOR UPDATE;
  IF NOT FOUND THEN
    RETURN false;
  END IF;
  IF u.bloqueado_hasta IS NOT NULL AND u.bloqueado_hasta > now() THEN
    RETURN false;
  END IF;

  v_ok := u.pin_hash = crypt(p_pin, u.pin_hash);
  PERFORM set_config('app.usuario_id', p_usuario_id::text, true);

  IF v_ok THEN
    UPDATE usuario
       SET intentos_fallidos = 0, bloqueado_hasta = NULL, ultimo_acceso = now()
     WHERE id = p_usuario_id;
  ELSE
    UPDATE usuario
       SET intentos_fallidos = intentos_fallidos + 1,
           bloqueado_hasta = CASE WHEN intentos_fallidos + 1 >= 5
                                  THEN now() + interval '5 minutes' END
     WHERE id = p_usuario_id;
  END IF;
  RETURN v_ok;
END $$;

-- -----------------------------------------------------------------------------
-- auditoria (inmutable; sin columnas de control propias)
-- -----------------------------------------------------------------------------

CREATE TABLE auditoria (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  tabla       text        NOT NULL,
  registro_id bigint      NOT NULL,
  accion      text        NOT NULL CHECK (accion IN ('INSERT', 'UPDATE', 'DELETE')),
  usuario_id  bigint      NOT NULL REFERENCES usuario (id),
  fecha       timestamptz NOT NULL DEFAULT now(),
  antes       jsonb,
  despues     jsonb
);
CREATE INDEX auditoria_registro_ix ON auditoria (tabla, registro_id, fecha);
CREATE INDEX auditoria_fecha_ix    ON auditoria (fecha);

CREATE FUNCTION trg_auditoria_inmutable() RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  RAISE EXCEPTION 'La auditoría no se puede modificar ni borrar';
END $$;
CREATE TRIGGER t00_inmutable BEFORE UPDATE OR DELETE ON auditoria
  FOR EACH ROW EXECUTE FUNCTION trg_auditoria_inmutable();
CREATE TRIGGER t00_inmutable_truncate BEFORE TRUNCATE ON auditoria
  FOR EACH STATEMENT EXECUTE FUNCTION trg_auditoria_inmutable();

-- Usuario «Sistema» (id 1): firma la migración desde el Excel y los procesos
-- automáticos. No puede iniciar sesión.
SELECT set_config('app.usuario_id', '1', true);
INSERT INTO usuario (id, nombre, rol, activo, es_sistema)
  OVERRIDING SYSTEM VALUE
  VALUES (1, 'Sistema', 'titular', false, true);
SELECT setval(pg_get_serial_sequence('usuario', 'id'), 1);

-- -----------------------------------------------------------------------------
-- configuracion
-- -----------------------------------------------------------------------------

CREATE TABLE configuracion (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  clave       text  NOT NULL UNIQUE CHECK (clave ~ '^[a-z0-9_]+(\.[a-z0-9_]+)*$'),
  valor       jsonb NOT NULL,
  descripcion text
);
SELECT preparar_tabla('configuracion');

-- -----------------------------------------------------------------------------
-- contador: numeración sin repeticiones (pedidos y, más adelante, otras series)
-- -----------------------------------------------------------------------------

CREATE TABLE contador (
  id     bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  serie  text    NOT NULL CHECK (serie ~ '^[A-Z]{1,3}$'),
  anio   integer NOT NULL CHECK (anio BETWEEN 2000 AND 2999),
  ultimo integer NOT NULL CHECK (ultimo >= 0),
  CONSTRAINT contador_serie_anio_uq UNIQUE (serie, anio)
);
SELECT preparar_tabla('contador', p_auditar => false);

-- Siguiente número de la serie y año. La fila queda bloqueada hasta el final de
-- la transacción: dos Macs a la vez nunca obtienen el mismo número, y si la
-- transacción se deshace, el número no se pierde.
CREATE FUNCTION siguiente_numero(p_serie text, p_anio integer) RETURNS integer
LANGUAGE sql SECURITY DEFINER SET search_path = public, pg_temp
AS $$
  INSERT INTO contador AS c (serie, anio, ultimo)
  VALUES (p_serie, p_anio, 1)
  ON CONFLICT (serie, anio) DO UPDATE SET ultimo = c.ultimo + 1
  RETURNING ultimo
$$;

-- -----------------------------------------------------------------------------
-- Permisos del rol de la app
-- -----------------------------------------------------------------------------

GRANT USAGE ON SCHEMA public TO gestiofoto_app;

GRANT SELECT (id, nombre, rol, activo, es_sistema, intentos_fallidos, bloqueado_hasta,
              ultimo_acceso, creado_en, creado_por, actualizado_en, actualizado_por,
              version)
  ON usuario TO gestiofoto_app;
GRANT UPDATE (nombre, rol, activo) ON usuario TO gestiofoto_app;

GRANT SELECT                 ON auditoria     TO gestiofoto_app;
GRANT SELECT, INSERT, UPDATE ON configuracion TO gestiofoto_app;
GRANT SELECT                 ON contador      TO gestiofoto_app;

REVOKE EXECUTE ON FUNCTION crear_usuario(text, text, text),
                           establecer_pin(bigint, text),
                           verificar_pin(bigint, text),
                           siguiente_numero(text, integer),
                           es_titular(bigint)
  FROM PUBLIC;
GRANT EXECUTE ON FUNCTION crear_usuario(text, text, text),
                          establecer_pin(bigint, text),
                          verificar_pin(bigint, text),
                          siguiente_numero(text, integer),
                          es_titular(bigint)
  TO gestiofoto_app;
