-- =============================================================================
-- seed.sql — datos iniciales. Se ejecuta tras las migraciones, en una
-- transacción, firmado por el usuario Sistema. Se puede repetir sin duplicar.
-- Los tipos de trabajo, conceptos, clientes y tarifa vienen de la migración del
-- Excel (Tools/migrate_excel), no de aquí.
-- =============================================================================

SELECT set_config('app.usuario_id', '1', true);

-- Formas de pago (códigos antiguos del Excel: 20, 7, 10 — PDF §3)
INSERT INTO forma_pago (codigo_antiguo, nombre, tipo, orden) VALUES
  (20, 'Efectivo',      'efectivo',      1),
  (7,  'Bizum',         'bizum',         2),
  (10, 'Transferencia', 'transferencia', 3)
ON CONFLICT (codigo_antiguo) DO NOTHING;

-- Configuración inicial (se completa en Ajustes)
INSERT INTO configuracion (clave, valor, descripcion) VALUES
  ('tienda.nombre',               '""',                       'Nombre de la tienda'),
  ('tienda.nif',                  '""',                       'NIF de la tienda'),
  ('tienda.direccion',            '""',                       'Dirección para recibos'),
  ('tienda.iban',                 '""',                       'IBAN que aparece en el recibo'),
  ('recibo.texto_pie',            '"No se admiten tarjetas. Sí Bizum."', 'Texto al pie del recibo'),
  ('presupuesto.validez_dias',    '30',                       'Días de validez de un presupuesto'),
  ('sesion.bloqueo_minutos',      '10',                       'Bloqueo de sesión sin uso'),
  ('pedidos.carpetas_raiz',       '[]',                       'Carpetas raíz de los trabajos (Macs y NAS)'),
  ('laboratorio.etiqueta_enviado','"Naranja"',                'Etiqueta del Finder = enviado al laboratorio'),
  ('laboratorio.etiqueta_recibido','"Amarillo"',              'Etiqueta del Finder = recibido'),
  ('mensajes.pedido_listo',
   '"Hola {nombre}, tu pedido {codigo} ya está listo para recoger. Pendiente: {pendiente} €."',
   'Plantilla de aviso por WhatsApp o email'),
  ('copias.carpeta',              'null',                     'Carpeta de las copias de seguridad'),
  ('copias.hora',                 '"02:00"',                  'Hora de la copia nocturna'),
  ('copias.conservar_diarias',    '30',                       'Copias diarias que se guardan'),
  ('copias.conservar_mensuales',  '12',                       'Copias mensuales que se guardan')
ON CONFLICT (clave) DO NOTHING;
