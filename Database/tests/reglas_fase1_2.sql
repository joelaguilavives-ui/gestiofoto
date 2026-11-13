-- =============================================================================
-- Pruebas del esquema (fases 1 y 2). Se ejecutan con:
--   psql -v ON_ERROR_STOP=1 -1 -f Database/tests/reglas_fase1_2.sql
-- sobre una base con las migraciones y el seed aplicados. Todo va en una
-- transacción que se deshace al final: no deja datos.
-- Trabaja con el rol de la app para comprobar también los permisos.
-- =============================================================================

SET ROLE gestiofoto_app;
SELECT set_config('app.usuario_id', '1', true);   -- Sistema crea el primer titular

-- Ayuda: comprueba que una sentencia falla
CREATE FUNCTION pg_temp.debe_fallar(p_sql text, p_que text) RETURNS void
LANGUAGE plpgsql AS $$
BEGIN
  BEGIN
    EXECUTE p_sql;
  EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'rechazado como se esperaba (%): %', p_que, SQLERRM;
    RETURN;
  END;
  RAISE EXCEPTION 'Debería haber fallado: %', p_que;
END $$;

DO $$
DECLARE
  v_titular bigint;
  v_tt bigint; v_prod bigint; v_prod2 bigint; v_t1 bigint; v_t2 bigint; v_t3 bigint;
  v_cli bigint; v_cli2 bigint; v_ev bigint;
  v_ped bigint; v_pres bigint;
  v_efectivo bigint;
  r record;
  v_codigo text;
  v_n integer;
BEGIN
  -- ---------------------------------------------------------------- usuarios
  v_titular := crear_usuario('Titular', 'titular', '1234');
  PERFORM set_config('app.usuario_id', v_titular::text, true);

  ASSERT verificar_pin(v_titular, '1234'), 'PIN correcto aceptado';
  ASSERT NOT verificar_pin(v_titular, '9999'), 'PIN incorrecto rechazado';
  PERFORM pg_temp.debe_fallar($q$SELECT crear_usuario('Corto', 'titular', '12')$q$, 'PIN de 2 cifras');
  PERFORM pg_temp.debe_fallar('SELECT pin_hash FROM usuario', 'la app no lee pin_hash');
  PERFORM pg_temp.debe_fallar(
    $q$INSERT INTO auditoria (tabla, registro_id, accion, usuario_id) VALUES ('x', 1, 'INSERT', 1)$q$,
    'la app no escribe en auditoria');

  -- ---------------------------------------------------------------- catálogo
  INSERT INTO tipo_trabajo (codigo_antiguo, nombre) VALUES (12, 'Serveis tenda') RETURNING id INTO v_tt;
  INSERT INTO producto (nombre, categoria) VALUES ('Fotos papel', 'fotos') RETURNING id INTO v_prod;
  INSERT INTO producto (nombre, categoria) VALUES ('Foam', 'foam') RETURNING id INTO v_prod2;
  INSERT INTO tamano (nombre, orden) VALUES ('10x15', 1) RETURNING id INTO v_t1;
  INSERT INTO tamano (nombre, orden) VALUES ('20x30', 2) RETURNING id INTO v_t2;
  INSERT INTO tamano (nombre, orden) VALUES ('30x40', 3) RETURNING id INTO v_t3;
  INSERT INTO precio (producto_id, tamano_id, vigente_desde, importe) VALUES
    (v_prod,  v_t1, DATE '2026-01-01', 20.00),
    (v_prod,  v_t2, DATE '2026-01-01', 25.00),
    (v_prod2, v_t2, DATE '2026-01-01', 30.00);
  -- subida de precio y retirada de una combinación
  INSERT INTO precio (producto_id, tamano_id, vigente_desde, importe) VALUES
    (v_prod, v_t1, DATE '2026-06-01', 22.00);
  INSERT INTO precio (producto_id, tamano_id, vigente_desde, disponible) VALUES
    (v_prod2, v_t2, DATE '2026-06-01', false);

  ASSERT precio_vigente(v_prod, v_t1, DATE '2026-03-01') = 20.00, 'precio antes de la subida';
  ASSERT precio_vigente(v_prod, v_t1, DATE '2026-07-01') = 22.00, 'precio tras la subida';
  ASSERT precio_vigente(v_prod2, v_t2, DATE '2026-07-01') IS NULL, 'combinación retirada';
  ASSERT (SELECT count(*) FROM tarifa_en(DATE '2026-07-01')) = 2, 'tarifa de julio: 2 combinaciones';

  SELECT id INTO v_efectivo FROM forma_pago WHERE tipo = 'efectivo';

  -- ---------------------------------------------------------------- clientes
  INSERT INTO cliente (codigo, nombre, telefono1) VALUES (1535, 'Nombre Apellido', '600111222')
    RETURNING id INTO v_cli;
  ASSERT (SELECT count(*) FROM buscar_clientes_parecidos('nombre apellído')) = 1, 'duplicado por nombre';
  ASSERT (SELECT motivo FROM buscar_clientes_parecidos('Otro', '600111222')) = 'telefono',
    'duplicado por teléfono';
  PERFORM pg_temp.debe_fallar($q$INSERT INTO cliente (nombre, telefono1) VALUES ('X', '600-111')$q$,
    'teléfono sin normalizar');

  -- ---------------------------------------------------------------- pedido (caso PDF fase 2)
  -- 2 líneas de tarifa + 1 libre + descuento: 63,00 − 2,00 = 61,00 €
  INSERT INTO pedido (cliente_id, fecha, tipo_trabajo_id)
    VALUES (v_cli, DATE '2026-03-10', v_tt) RETURNING id, codigo INTO v_ped, v_codigo;
  ASSERT v_codigo = '26P0001-C1535-Nombre Apellido', 'formato de código: ' || v_codigo;

  INSERT INTO pedido_linea (pedido_id, orden, origen, producto_id, tamano_id, cantidad,
                            precio_unitario, descuento_pct)
    VALUES (v_ped, 1, 'tarifa', v_prod, v_t1, 1, 20.00, 10),
           (v_ped, 2, 'tarifa', v_prod, v_t2, 1, 25.00, 0);
  INSERT INTO pedido_linea (pedido_id, orden, origen, descripcion, cantidad, precio_unitario)
    VALUES (v_ped, 3, 'libre', 'Retoque', 1, 18.00);

  SELECT * INTO r FROM pedido_resumen WHERE pedido_id = v_ped;
  ASSERT r.subtotal = 63.00, 'subtotal 63,00: ' || r.subtotal;
  ASSERT r.total_descuento = 2.00, 'descuento 2,00: ' || r.total_descuento;
  ASSERT r.total = 61.00, 'total 61,00: ' || r.total;

  -- precio cambiado a mano → manual
  INSERT INTO pedido_linea (pedido_id, orden, origen, producto_id, tamano_id, cantidad, precio_unitario)
    VALUES (v_ped, 4, 'tarifa', v_prod, v_t1, 3, 15.00);
  ASSERT (SELECT origen FROM pedido_linea WHERE pedido_id = v_ped AND orden = 4) = 'manual',
    'precio distinto de tarifa queda como manual';
  -- redondeo por línea: 3 × 0,335 = 1,005 → 1,01
  INSERT INTO pedido_linea (pedido_id, orden, origen, descripcion, cantidad, precio_unitario, descuento_pct)
    VALUES (v_ped, 5, 'libre', 'Prueba redondeo', 3, 0.67, 50);
  ASSERT (SELECT importe FROM pedido_linea WHERE pedido_id = v_ped AND orden = 5) = 1.01,
    'redondeo de línea a 2 decimales';
  -- combinación sin precio
  PERFORM pg_temp.debe_fallar(format(
    $q$INSERT INTO pedido_linea (pedido_id, orden, origen, producto_id, tamano_id, cantidad, precio_unitario)
       VALUES (%s, 6, 'tarifa', %s, %s, 1, 1)$q$, v_ped, v_prod, v_t3), 'tamaño sin precio');

  -- ---------------------------------------------------------------- cobros y pendiente
  DELETE FROM pedido_linea WHERE pedido_id = v_ped AND orden IN (4, 5);
  INSERT INTO cobro (pedido_id, fecha, importe, forma_pago_id) VALUES (v_ped, DATE '2026-03-10', 20, v_efectivo);
  INSERT INTO cobro (pedido_id, fecha, importe, forma_pago_id) VALUES (v_ped, DATE '2026-03-20', 41.50, v_efectivo);
  INSERT INTO pedido_ajuste (pedido_id, tipo, importe, motivo) VALUES (v_ped, 'sobrante', -0.50, 'cobrado de más');
  ASSERT (SELECT pendiente FROM pedido_resumen WHERE pedido_id = v_ped) = 0, 'pendiente 0 tras cobros y sobrante';
  PERFORM pg_temp.debe_fallar(format(
    $q$INSERT INTO pedido_ajuste (pedido_id, tipo, importe) VALUES (%s, 'sobrante', 1)$q$, v_ped),
    'sobrante positivo');

  -- ---------------------------------------------------------------- versión y auditoría
  ASSERT (SELECT version FROM pedido WHERE id = v_ped) = 1, 'versión inicial 1';
  UPDATE pedido SET notas = 'nota' WHERE id = v_ped AND version = 1;
  ASSERT FOUND, 'actualización con versión correcta';
  UPDATE pedido SET notas = 'otra' WHERE id = v_ped AND version = 1;
  ASSERT NOT FOUND, 'conflicto: versión antigua no actualiza nada';
  ASSERT (SELECT count(*) FROM auditoria WHERE tabla = 'pedido' AND registro_id = v_ped) = 2,
    'auditoría: alta + cambio';
  PERFORM pg_temp.debe_fallar('DELETE FROM pedido WHERE id = ' || v_ped, 'la app no borra pedidos');

  -- ---------------------------------------------------------------- estados
  UPDATE pedido SET estado = 'enviado' WHERE id = v_ped;
  PERFORM set_config('app.origen', 'finder', true);
  UPDATE pedido SET estado = 'recibido' WHERE id = v_ped;
  PERFORM set_config('app.origen', '', true);
  ASSERT (SELECT count(*) FROM pedido_estado_log WHERE pedido_id = v_ped) = 3, 'log: alta + 2 cambios';
  ASSERT (SELECT origen FROM pedido_estado_log WHERE pedido_id = v_ped AND estado_nuevo = 'recibido') = 'finder',
    'origen Finder registrado';
  UPDATE pedido SET codigo = 'X', numero = 99 WHERE id = v_ped;
  ASSERT (SELECT codigo FROM pedido WHERE id = v_ped) = v_codigo, 'el código no cambia';
  PERFORM pg_temp.debe_fallar(format($q$UPDATE pedido SET estado = 'anulado' WHERE id = %s$q$, v_ped),
    'anular sin motivo');

  -- ---------------------------------------------------------------- presupuesto
  INSERT INTO pedido (cliente_id, fecha, tipo_trabajo_id, es_presupuesto, estado)
    VALUES (v_cli, DATE '2026-04-01', v_tt, true, 'presupuesto') RETURNING id INTO v_pres;
  ASSERT (SELECT codigo FROM pedido WHERE id = v_pres) IS NULL, 'presupuesto sin número';
  PERFORM pg_temp.debe_fallar(format(
    $q$INSERT INTO cobro (pedido_id, importe, forma_pago_id) VALUES (%s, 10, %s)$q$, v_pres, v_efectivo),
    'cobro de presupuesto');
  UPDATE pedido SET es_presupuesto = false, estado = 'encargado' WHERE id = v_pres;
  ASSERT (SELECT codigo FROM pedido WHERE id = v_pres) = '26P0002-C1535-Nombre Apellido',
    'presupuesto convertido recibe el siguiente número';
  PERFORM pg_temp.debe_fallar(format(
    $q$UPDATE pedido SET es_presupuesto = true, estado = 'presupuesto' WHERE id = %s$q$, v_pres),
    'pedido no vuelve a presupuesto');

  -- numeración por año
  INSERT INTO pedido (cliente_id, fecha, tipo_trabajo_id)
    VALUES (v_cli, DATE '2027-01-02', v_tt) RETURNING codigo INTO v_codigo;
  ASSERT v_codigo LIKE '27P0001-%', 'el número se reinicia cada año: ' || v_codigo;

  -- anulación
  UPDATE pedido SET estado = 'anulado', motivo_anulacion = 'cliente no lo quiere' WHERE id = v_pres;
  PERFORM pg_temp.debe_fallar(format($q$UPDATE pedido SET estado = 'encargado', motivo_anulacion = NULL WHERE id = %s$q$, v_pres),
    'reactivar anulado');
  PERFORM pg_temp.debe_fallar(format(
    $q$INSERT INTO pedido_linea (pedido_id, orden, origen, descripcion, cantidad, precio_unitario)
       VALUES (%s, 1, 'libre', 'x', 1, 1)$q$, v_pres), 'línea en pedido anulado');

  -- ---------------------------------------------------------------- fusión de clientes
  INSERT INTO cliente (nombre) VALUES ('Nombre Apellido (dup)') RETURNING id INTO v_cli2;
  INSERT INTO evento (cliente_id, tipo, fecha) VALUES (v_cli2, 'comunion', DATE '2026-05-10') RETURNING id INTO v_ev;
  INSERT INTO pedido (cliente_id, fecha, tipo_trabajo_id, evento_id)
    VALUES (v_cli2, DATE '2026-05-01', v_tt, v_ev);
  PERFORM pg_temp.debe_fallar(format(
    $q$INSERT INTO pedido (cliente_id, tipo_trabajo_id, evento_id) VALUES (%s, %s, %s)$q$, v_cli, v_tt, v_ev),
    'evento de otro cliente');
  PERFORM fusionar_clientes(v_cli, v_cli2);
  ASSERT (SELECT count(*) FROM pedido WHERE cliente_id = v_cli2) = 0, 'pedidos movidos';
  ASSERT (SELECT cliente_id FROM evento WHERE id = v_ev) = v_cli, 'evento movido';
  ASSERT (SELECT fusionado_en FROM cliente WHERE id = v_cli2) = v_cli, 'ficha absorbida marcada';
  ASSERT NOT (SELECT activo FROM cliente WHERE id = v_cli2), 'ficha absorbida desactivada';

  -- ---------------------------------------------------------------- inmutabilidad y firma
  RESET ROLE;
  PERFORM pg_temp.debe_fallar('DELETE FROM auditoria', 'auditoría inmutable (incluso para el propietario)');
  PERFORM set_config('app.usuario_id', '', true);
  PERFORM pg_temp.debe_fallar($q$INSERT INTO tamano (nombre) VALUES ('sin firma')$q$, 'cambio sin usuario');

  RAISE NOTICE 'OK: todas las pruebas de fases 1 y 2 pasan';
END $$;

ROLLBACK;
