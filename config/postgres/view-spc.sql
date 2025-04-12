CREATE OR REPLACE VIEW catalogos_agrupados AS
SELECT row_number() OVER () AS id, -- Campo ficticio de ID
       jsonb_object_agg("tipoCatalogo", catalogo_items) AS catalogos_agrupados
FROM (
    SELECT "tipoCatalogo", jsonb_agg(jsonb_build_object(
        'id', id,
        'codigo', codigo,
        'valor', COALESCE(valor, '')
    )) AS catalogo_items
    FROM "Catalogo"
    GROUP BY "tipoCatalogo"
) AS subquery;


CREATE OR REPLACE FUNCTION facturalink.fn_get_info_sucursal_documento(
  p_sucursal_id INT,
  p_codigo_documento TEXT
)
RETURNS JSON AS $$
DECLARE
  result JSON;
BEGIN
  SELECT json_build_object(
    'empresa', json_build_object(
      'id', e.id,
      'nombre', e.nombre,
      'nit', e.nit,
      'nrc', e.nrc,
      'telefono', e.telefono,
      'correo', e.correo,
      'logo', e.logo,
      'actividadesEconomicas', (
        SELECT json_agg(json_build_object(
          'codigo', cae.codigo,
          'valor', cae.valor
        ))
        FROM "facturalink"."EmpresaActividadEconomica" eae
        JOIN "facturalink"."ActividadEconomica" cae ON cae.id = eae."actividadEconomicaId"
        WHERE eae."empresaId" = e.id
      )
    ),
    'documento', json_build_object(
      'id', d.id,
      'codigo', d.codigo,
      'valor', d.valor,
      'abreviatura', d.abreviatura,
      'ambiente', json_build_object(
        'id', c.id,
        'codigo', c.codigo,
        'valor', c.valor,
        'descripcion', c.descripcion
      )
    ),
    'credencial', json_build_object(
      'id', cr.id,
      'usuario', cr.usuario,
      'password', cr.password,
      'clavePublica', cr."clavePublica",
      'clavePrivada', cr."clavePrivada",
      'nombreCliente', cr."nombreCliente",
      'accessToken', cr."accessToken",
      'uriRecepcion', cr."uriRecepcion",
      'uriAnulacion', cr."uriAnulacion",
      'uriAuth', cr."uriAuth",
      'uriContigencia', cr."uriContigencia"
    ),
    'sucursal', json_build_object(
      'nit', e.nit,
      'nrc', e.nrc,
      'nombre', e.nombre,
      'codActividad', NULL,
      'descActividad', NULL,
      'codigoDte',  s."codigoDte",
      'nombreComercial', s.nombre,
      'tipoEstablecimiento', s."tipoEstablecimiento",
      'direccion', json_build_object(
        'departamento', dept.codigo,
        'municipio', muni.codigo,
        'complemento', s.direccion
      ),
      'telefono', s.telefono,
      'correo', s.email,
      'codEstableMH', s."codEstableMH",
      'codEstable', s."codEstable",
      'codPuntoVentaMH', s."codPuntoVentaMH",
      'codPuntoVenta', s."codPuntoVenta"
    )
  )
  INTO result
  FROM "facturalink"."Sucursal" s
  JOIN "facturalink"."Empresa" e ON s."empresaId" = e.id
  JOIN "facturalink"."DocumentosDte" d ON d."abreviatura" = p_codigo_documento
  JOIN "facturalink"."Catalogo" c ON d."ambienteId" = c.id
  LEFT JOIN "facturalink"."Credenciales" cr ON cr."empresaId" = e.id AND cr."ambienteId" = d."ambienteId"
  LEFT JOIN "facturalink"."Catalogo" dept ON dept.id = s."departamentoId"
  LEFT JOIN "facturalink"."Catalogo" muni ON muni.id = s."municipioId"
  WHERE s.id = p_sucursal_id;

  RETURN result;
END;
$$ LANGUAGE plpgsql;





SELECT facturalink.fn_get_info_sucursal_documento(3, 'FE');

SELECT *
FROM "facturalink"."Sucursal"

WHERE id = 2;
SELECT *
FROM "facturalink"."DocumentosDte"
WHERE codigo = 'FE';



CREATE OR REPLACE FUNCTION generate_dte_sequence(tipoDte TEXT, prefijo TEXT)
RETURNS TEXT AS $$
DECLARE
    seq_name TEXT;
    seq_num BIGINT;
    formatted_seq TEXT;
BEGIN
    -- Nombre único de la secuencia para ese prefijo
    seq_name := 'dte_seq_' || lower(replace(prefijo, '-', '_'));

    -- Intentar obtener el siguiente valor de la secuencia
    BEGIN
        EXECUTE format('SELECT nextval(%L)', seq_name) INTO seq_num;
    EXCEPTION
        WHEN undefined_table THEN
            -- Si la secuencia no existe, crearla y volver a obtener el valor
            EXECUTE format('CREATE SEQUENCE %I START 1', seq_name);
            EXECUTE format('SELECT nextval(%L)', seq_name) INTO seq_num;
    END;

    -- Formatear correlativo a 15 dígitos
    formatted_seq := LPAD(seq_num::TEXT, 15, '0');

    -- Retornar el número de control con tipoDte dinámico
    RETURN 'DTE-' || tipoDte || '-' || prefijo || '-' || formatted_seq;
END;
$$ LANGUAGE plpgsql;



SELECT generate_dte_sequence('01', 'ENZ00025');
DTE-01-ENZ00025-000000000000007
DTE-01-ENZ00025-000000000000002

SELECT n.nspname as "Schema",
       p.proname as "Function Name"
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE p.proname = 'generate_dte_sequence';




CREATE SCHEMA IF NOT EXISTS org;
CREATE SCHEMA IF NOT EXISTS core;

ALTER TABLE "facturalink"."Sucursal"
ADD COLUMN "empresaId" INTEGER;

ALTER TABLE "facturalink"."Sucursal"
ADD COLUMN "codigoDte" VARCHAR(10);

-- Asegurar unicidad del campo
ALTER TABLE "facturalink"."Sucursal"
ADD CONSTRAINT "Sucursal_codigoDte_key" UNIQUE ("codigoDte");



CREATE OR REPLACE FUNCTION facturalink.fn_get_info_receptor(
  p_receptor_id INT,
  p_is_cliente BOOLEAN,
  p_cod_actividad TEXT
)
RETURNS JSON AS $$
DECLARE
  result JSON;
  actividad_id INT;
BEGIN
  -- Buscar ID de la actividad económica
  SELECT id INTO actividad_id
  FROM facturalink."ActividadEconomica"
  WHERE codigo = p_cod_actividad;

  IF actividad_id IS NULL THEN
    RAISE EXCEPTION 'Actividad económica con código % no encontrada', p_cod_actividad;
  END IF;

  IF p_is_cliente THEN
    -- Cliente
    SELECT json_build_object(
      'tipoDocumento', c."tipoDocumento",
      'numDocumento',
        CASE c."tipoDocumento"
          WHEN '13' THEN regexp_replace(c."numDocumento", '(\d{8})(\d)', '\1-\2') -- DUI
          WHEN '02' THEN regexp_replace(c."numDocumento", '(\d{4})(\d{6})(\d{3})(\d)', '\1-\2-\3-\4') -- NIT
          ELSE c."numDocumento"
        END,
      'nrc', c."nrc",
      'nombre', c."nombre",
      'codActividad', ae.codigo,
      'descActividad', ae.valor,
      'direccion', json_build_object(
        'departamento', dept.codigo,
        'municipio', muni.codigo,
        'complemento', c.direccion
      ),
      'telefono', c."telefono",
      'correo', c."email"
    )
    INTO result
    FROM facturalink."Cliente" c
    JOIN facturalink."ClienteActividadEconomica" cae ON cae."clienteId" = c.id
    JOIN facturalink."ActividadEconomica" ae ON ae.id = cae."actividadEconomicaId"
    LEFT JOIN facturalink."Catalogo" dept ON dept.id = c."departamentoId"
    LEFT JOIN facturalink."Catalogo" muni ON muni.id = c."municipioId"
    WHERE c.id = p_receptor_id AND cae."actividadEconomicaId" = actividad_id
    LIMIT 1;
  ELSE
    -- Empresa
    SELECT json_build_object(
      'tipoDocumento', e."tipoDocumento",
      'numDocumento',
        CASE e."tipoDocumento"
          WHEN '13' THEN regexp_replace(e."nit", '(\d{8})(\d)', '\1-\2') -- DUI
          WHEN '02' THEN regexp_replace(e."nit", '(\d{4})(\d{6})(\d{3})(\d)', '\1-\2-\3-\4') -- NIT
          ELSE e."nit"
        END,
      'nrc', e."nrc",
      'nombre', e."nombre",
      'codActividad', ae.codigo,
      'descActividad', ae.valor,
      'direccion', json_build_object(
        'departamento', NULL,
        'municipio', NULL,
        'complemento', e."direccion"
      ),
      'telefono', e."telefono",
      'correo', e."correo"
    )
    INTO result
    FROM facturalink."Empresa" e
    JOIN facturalink."EmpresaActividadEconomica" eae ON eae."empresaId" = e.id
    JOIN facturalink."ActividadEconomica" ae ON ae.id = eae."actividadEconomicaId"
    WHERE e.id = p_receptor_id AND ae.id = actividad_id
    LIMIT 1;
  END IF;

  IF result IS NULL THEN
    RAISE EXCEPTION 'No se encontró receptor con ID % y actividad económica %', p_receptor_id, p_cod_actividad;
  END IF;

  RETURN result;
END;
$$ LANGUAGE plpgsql;


SELECT facturalink.fn_get_info_receptor(2, true,'69200');



CREATE OR REPLACE FUNCTION facturalink.get_empresa_by_keycloak_group(p_group_id TEXT)
RETURNS JSON AS $$
DECLARE
  v_empresa_id INT;
  v_resultado JSON;
BEGIN
  -- Obtener la empresa relacionada al keycloakGroupId
  SELECT id INTO v_empresa_id
  FROM facturalink."Empresa"
  WHERE "keycloakGroupId" = p_group_id
    AND "estadoRt" = 'ACTIVO';

  IF v_empresa_id IS NULL THEN
    RAISE EXCEPTION 'Empresa no encontrada para el keycloakGroupId: %', p_group_id;
  END IF;

  -- Devolver la estructura como JSON, incluyendo documentosDte
  SELECT json_build_object(
    'empresa', (
      SELECT row_to_json(e)
      FROM (
        SELECT *
        FROM facturalink."Empresa"
        WHERE id = v_empresa_id
      ) e
    ),
    'sucursales', (
      SELECT json_agg(s)
      FROM (
        SELECT *
        FROM facturalink."Sucursal"
        WHERE "empresaId" = v_empresa_id
          AND "estadoRt" = 'ACTIVO'
      ) s
    ),
    'actsEconomica', (
      SELECT json_agg(ae)
      FROM (
        SELECT *
        FROM facturalink."EmpresaActividadEconomica" eae
        JOIN facturalink."ActividadEconomica" ae ON ae.id = eae."actividadEconomicaId"
        WHERE eae."empresaId" = v_empresa_id
      ) ae
    ),
    'documentosDte', (
      SELECT json_agg(dd)
      FROM (
        SELECT d.*
        FROM facturalink."EmpresaDocumentosDte" ed
        JOIN facturalink."DocumentosDte" d ON d.id = ed."documentosDteId"
        WHERE ed."empresaId" = v_empresa_id
      ) dd
    )
  ) INTO v_resultado;

  RETURN v_resultado;
END;
$$ LANGUAGE plpgsql;



SELECT * FROM facturalink.get_empresa_by_keycloak_group('el_nazareno');



SELECT * FROM information_schema.tables
WHERE table_schema = 'facturalink' AND table_name = 'EmpresaClientes';
