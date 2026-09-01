-- ─── V10: Campos de teleconsulta (Daily.co) em AGENDAMENTO ────────────────────
-- TASK-10 (FEAT-01). Suporte a sessões de vídeo via Daily.co no agendamento
-- clínico. Colunas nullable / com DEFAULT para não quebrar linhas existentes.
-- Autoridade do schema: Flyway (D-10). O .NET (dono de AGENDAMENTO) espelha
-- estes campos via migration EF Core apenas como evidência FIAP.

ALTER TABLE AGENDAMENTO
    ADD DS_SALA_URL VARCHAR2(512);

ALTER TABLE AGENDAMENTO
    ADD DS_PROVEDOR_VIDEO VARCHAR2(30);

ALTER TABLE AGENDAMENTO
    ADD ST_TELECONSULTA CHAR(1) DEFAULT 'N' NOT NULL;

ALTER TABLE AGENDAMENTO
    ADD DT_INICIO_SESSAO TIMESTAMP;

ALTER TABLE AGENDAMENTO
    ADD DT_FIM_SESSAO TIMESTAMP;

ALTER TABLE AGENDAMENTO
    ADD CONSTRAINT CHK_AGENDA_TELECONSULTA CHECK (ST_TELECONSULTA IN ('S', 'N'));

COMMENT ON COLUMN AGENDAMENTO.DS_SALA_URL IS 'URL da sala de videochamada (Daily.co). Nunca logar como PII de terceiros.';
COMMENT ON COLUMN AGENDAMENTO.DS_PROVEDOR_VIDEO IS 'Provedor de vídeo usado (ex.: DAILY). Nullable até a sala ser criada.';
COMMENT ON COLUMN AGENDAMENTO.ST_TELECONSULTA IS 'S/N — indica se o agendamento é uma teleconsulta (CFMV 1.465/2022).';
COMMENT ON COLUMN AGENDAMENTO.DT_INICIO_SESSAO IS 'Timestamp de criação da sala de videochamada.';
COMMENT ON COLUMN AGENDAMENTO.DT_FIM_SESSAO IS 'Timestamp de encerramento da sessão de videochamada.';
