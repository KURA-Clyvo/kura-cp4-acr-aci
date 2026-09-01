-- =============================================================================
-- V5__agendamento_observacoes.sql
-- Adiciona campos Java-específicos em AGENDAMENTO de forma IDEMPOTENTE.
-- =============================================================================

DECLARE
  v_count NUMBER;
BEGIN
  -- 1. Verifica e adiciona as colunas
  SELECT COUNT(*) INTO v_count 
  FROM USER_TAB_COLS 
  WHERE TABLE_NAME = 'AGENDAMENTO' AND COLUMN_NAME = 'NM_PACIENTE';
  
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE '
      ALTER TABLE AGENDAMENTO ADD (
          NM_PACIENTE         VARCHAR2(200),
          DS_SERVICO          VARCHAR2(200),
          DS_OBSERVACOES      VARCHAR2(1000),
          DT_CRIACAO          TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
          DT_CONFIRMACAO      TIMESTAMP,
          DT_CANCELAMENTO     TIMESTAMP,
          DS_MOTIVO_CANCEL    VARCHAR2(500),
          ID_EVENTO_GERADO    NUMBER(10)
      )
    ';
  END IF;

  -- 2. Verifica e adiciona a Foreign Key
  SELECT COUNT(*) INTO v_count 
  FROM USER_CONSTRAINTS 
  WHERE CONSTRAINT_NAME = 'FK_AGEND_EVENTO';
  
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'ALTER TABLE AGENDAMENTO ADD CONSTRAINT FK_AGEND_EVENTO FOREIGN KEY (ID_EVENTO_GERADO) REFERENCES EVENTO_CLINICO(ID_EVENTO)';
  END IF;

  -- 3. Verifica e adiciona o Index
  SELECT COUNT(*) INTO v_count 
  FROM USER_INDEXES 
  WHERE INDEX_NAME = 'IDX_AGEND_EVENTO';
  
  IF v_count = 0 THEN
    EXECUTE IMMEDIATE 'CREATE INDEX IDX_AGEND_EVENTO ON AGENDAMENTO(ID_EVENTO_GERADO)';
  END IF;
END;
/

-- Comentários (podem sobrescrever livremente sem erro)
COMMENT ON COLUMN AGENDAMENTO.NM_PACIENTE      IS 'Nome do pet snapshot ao criar agendamento — denormalizado.';
COMMENT ON COLUMN AGENDAMENTO.DS_SERVICO       IS 'Descrição livre do serviço solicitado pelo tutor.';
COMMENT ON COLUMN AGENDAMENTO.DS_OBSERVACOES   IS 'Observações do tutor ao criar/reagendar.';
COMMENT ON COLUMN AGENDAMENTO.DT_CRIACAO       IS 'Preenchido pelo @CreatedDate JPA Auditing.';
COMMENT ON COLUMN AGENDAMENTO.DT_CANCELAMENTO  IS 'Preenchido por Agendamento.cancelar(motivo).';
COMMENT ON COLUMN AGENDAMENTO.ID_EVENTO_GERADO IS 'Quando ST_STATUS=REALIZADO, .NET preenche com ID_EVENTO_CLINICO gerado.';