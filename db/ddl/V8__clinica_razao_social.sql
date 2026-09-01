-- =============================================================================
-- V8__clinica_razao_social.sql
-- Corrige schema drift: Clinica.NmRazaoSocial existe no modelo EF/.NET desde a
-- migration EF "20260513140711_Schema_v4_BoolColumns_PKRename" (evidência FIAP),
-- mas nunca foi espelhada aqui — a coluna nunca existiu no schema real, e todo
-- POST /api/v1/auth/register-clinica falhava com ORA-00904 (identificador
-- inválido). Flyway é a única autoridade de DDL (CLAUDE.md) — a coluna nasce
-- aqui, a migration EF já existente no .NET passa a ser evidência retroativa.
-- =============================================================================

ALTER TABLE CLINICA ADD NM_RAZAO_SOCIAL VARCHAR2(150);

COMMENT ON COLUMN CLINICA.NM_RAZAO_SOCIAL IS
    'Razão social da clínica — opcional, distinto do nome fantasia (NM_CLINICA). Owned pelo .NET.';
