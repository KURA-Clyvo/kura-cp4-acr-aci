-- =============================================================================
-- V2__concurrency_idempotency.sql
-- Reforço de concorrência: índice de limpeza em IDEMPOTENCY_KEY.
-- Referência: §3.4 do plano v5.
-- =============================================================================

DECLARE
   v_count INTEGER;
BEGIN
   -- Verifica na tabela de metadados do Oracle se o índice já existe
   SELECT COUNT(*) INTO v_count FROM USER_INDEXES WHERE INDEX_NAME = 'IDX_IDEMPOT_CRIACAO';
   
   -- Só executa a criação se o índice não for encontrado
   IF v_count = 0 THEN
      EXECUTE IMMEDIATE 'CREATE INDEX IDX_IDEMPOT_CRIACAO ON IDEMPOTENCY_KEY(DT_CRIACAO)';
   END IF;
END;
/

-- O comando COMMENT ON TABLE não falha se a tabela já tiver comentário, ele apenas sobrescreve.
COMMENT ON TABLE IDEMPOTENCY_KEY IS
    'Exactly-once para POSTs sensíveis (CONSENTIMENTO). TTL 24h. Limpeza via job agendado — IDX_IDEMPOT_CRIACAO otimiza o DELETE em lote.';