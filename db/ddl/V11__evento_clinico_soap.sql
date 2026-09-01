-- ─── V11: Draft de transcrição/SOAP em EVENTO_CLINICO ─────────────────────────
-- TASK-13 (FEAT-02). Suporte a transcrição de áudio (Whisper via Luna) e draft
-- SOAP (S/O/A/P) revisável pelo vet antes de confirmar. Colunas nullable / com
-- DEFAULT para não quebrar linhas existentes. Autoridade do schema: Flyway
-- (D-10). O .NET (dono de EVENTO_CLINICO) espelha estes campos via migration
-- EF Core apenas como evidência FIAP.
-- Princípio inegociável: nada vira SOAP "confirmado" sem ação explícita do vet
-- (ST_SOAP_CONFIRMADO nasce 'N' e só muda para 'S' via PUT .../soap).

ALTER TABLE EVENTO_CLINICO
    ADD DS_TRANSCRICAO CLOB;

ALTER TABLE EVENTO_CLINICO
    ADD DS_SOAP_S CLOB;

ALTER TABLE EVENTO_CLINICO
    ADD DS_SOAP_O CLOB;

ALTER TABLE EVENTO_CLINICO
    ADD DS_SOAP_A CLOB;

ALTER TABLE EVENTO_CLINICO
    ADD DS_SOAP_P CLOB;

ALTER TABLE EVENTO_CLINICO
    ADD ST_SOAP_CONFIRMADO CHAR(1) DEFAULT 'N' NOT NULL;

ALTER TABLE EVENTO_CLINICO
    ADD CONSTRAINT CHK_EVENTO_SOAP_CONFIRMADO CHECK (ST_SOAP_CONFIRMADO IN ('S', 'N'));

COMMENT ON COLUMN EVENTO_CLINICO.DS_TRANSCRICAO IS 'Transcrição do áudio da consulta (Whisper via Luna). Nunca logar como PII clínica.';
COMMENT ON COLUMN EVENTO_CLINICO.DS_SOAP_S IS 'Draft SOAP — Subjetivo (heurística Luna, revisável pelo vet).';
COMMENT ON COLUMN EVENTO_CLINICO.DS_SOAP_O IS 'Draft SOAP — Objetivo (heurística Luna, revisável pelo vet).';
COMMENT ON COLUMN EVENTO_CLINICO.DS_SOAP_A IS 'Draft SOAP — Avaliação (heurística Luna, revisável pelo vet).';
COMMENT ON COLUMN EVENTO_CLINICO.DS_SOAP_P IS 'Draft SOAP — Plano (heurística Luna, revisável pelo vet).';
COMMENT ON COLUMN EVENTO_CLINICO.ST_SOAP_CONFIRMADO IS 'S/N — nasce N; só vira S via confirmação explícita do vet (PUT /eventos-clinicos/{id}/soap).';
