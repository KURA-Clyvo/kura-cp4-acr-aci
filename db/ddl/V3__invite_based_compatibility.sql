-- =============================================================================
-- V3__invite_based_compatibility.sql
-- Garante UK_CONTA_INVITE_USED e índice de busca por token de forma IDEMPOTENTE.
-- Referência: §3.5 do plano v5.
-- =============================================================================

DECLARE
  v_count NUMBER;
BEGIN
  -- 1. Verifica e cria a Unique Constraint (UK_CONTA_INVITE_USED)
  SELECT COUNT(*) INTO v_count 
  FROM USER_CONSTRAINTS 
  WHERE CONSTRAINT_NAME = 'UK_CONTA_INVITE_USED';
  
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE CONTA_TUTOR ADD CONSTRAINT UK_CONTA_INVITE_USED UNIQUE (ID_INVITE_USADO)';
  END IF;
  
  -- 2. Verifica e cria o Índice (IDX_INVITE_TOKEN_ATIVO)
  SELECT COUNT(*) INTO v_count 
  FROM USER_INDEXES 
  WHERE INDEX_NAME = 'IDX_INVITE_TOKEN_ATIVO';
  
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE INDEX IDX_INVITE_TOKEN_ATIVO ON INVITE_TUTOR (NR_TOKEN, ST_UTILIZADO, ST_ATIVO)';
  END IF;
END;
/

-- O comando COMMENT ON overwrites (sobrescreve) sem falhar, portanto pode ficar fora do bloco PL/SQL
COMMENT ON COLUMN CONTA_TUTOR.ID_INVITE_USADO IS
    'UK_CONTA_INVITE_USED: race condition → ORA-00001 → DataIntegrityViolationException → HTTP 409.';