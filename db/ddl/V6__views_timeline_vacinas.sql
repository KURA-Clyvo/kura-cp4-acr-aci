-- =============================================================================
-- V6__views_timeline_vacinas.sql
-- Atualiza aliases de colunas nas views para nomes canônicos usados pelas
-- entities Java: TimelinePet e VacinaVencendo.
--
-- VW_TIMELINE_PET:   ID_AGENDAMENTO → ID_EVENTO, DT_AGENDAMENTO → DT_EVENTO
-- VW_VACINAS_VENCENDO: adiciona DS_TIPO AS NM_VACINA, renomeia DT_VACINA → DT_PROXIMA_DOSE
--
-- Compatível com H2 Oracle mode (CREATE OR REPLACE VIEW) e Oracle 19c.
-- =============================================================================

CREATE OR REPLACE VIEW VW_TIMELINE_PET AS
SELECT
    a.ID_PET,
    a.ID_AGENDAMENTO  AS ID_EVENTO,
    p.NM_PET,
    a.DT_AGENDAMENTO  AS DT_EVENTO,
    a.DS_TIPO         AS DS_TIPO_EVENTO,
    a.ST_STATUS,
    a.ID_CLINICA,
    c.NM_CLINICA
FROM   AGENDAMENTO a
JOIN   PET          p ON p.ID_PET     = a.ID_PET
JOIN   CLINICA      c ON c.ID_CLINICA = a.ID_CLINICA
WHERE  a.ID_PET IS NOT NULL;

CREATE OR REPLACE VIEW VW_VACINAS_VENCENDO AS
SELECT
    p.ID_PET,
    p.NM_PET,
    a.ID_TUTOR,
    a.DS_TIPO         AS NM_VACINA,
    a.DT_AGENDAMENTO  AS DT_PROXIMA_DOSE,
    a.ID_CLINICA,
    c.NM_CLINICA
FROM   AGENDAMENTO a
JOIN   PET         p ON p.ID_PET     = a.ID_PET
JOIN   CLINICA     c ON c.ID_CLINICA = a.ID_CLINICA
WHERE  a.DS_TIPO   = 'VACINA'
  AND  a.ST_STATUS NOT IN ('CANCELADO','REALIZADO')
  AND  a.DT_AGENDAMENTO >= CURRENT_TIMESTAMP
  AND  a.DT_AGENDAMENTO <= CURRENT_TIMESTAMP + INTERVAL '30' DAY;
