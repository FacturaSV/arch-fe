-- 🔹 Crear esquema si no existe
CREATE SCHEMA IF NOT EXISTS keycloak_schema;

-- 🔹 Crear usuario solo si no existe
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'keycloak_userL4RT') THEN
        CREATE USER "keycloak_userL4RT" WITH PASSWORD 'S6ZWqBr2eE4J64MtNOnwYb';
    END IF;
END $$;

-- 🔹 Dar todos los privilegios sobre el esquema
GRANT ALL PRIVILEGES ON SCHEMA keycloak_schema TO "keycloak_userL4RT";

-- 🔹 Establecer el search_path por defecto
ALTER ROLE "keycloak_userL4RT" SET search_path TO keycloak_schema, public;
