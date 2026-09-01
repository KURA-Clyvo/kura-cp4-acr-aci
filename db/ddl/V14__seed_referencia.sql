-- =============================================================================
-- V14__seed_referencia.sql
-- TASK-37 (DB-02). Semeia o catálogo de referência (ESPECIE, RACA, TIPO_EVENTO,
-- MEDICAMENTO) como parte do schema versionado, para os dois profiles
-- (dev e prod).
--
-- CONTEXTO: os seeds existentes (db/callback/afterMigrate__seeds_dev.sql) só
-- carregam em profile dev (application-prod.yml não inclui classpath:db/callback
-- em spring.flyway.locations — ver application-prod.yml:38). O compose do
-- DevOps-Cloud roda prod. Resultado: `docker compose down -v && up -d` produz
-- um schema vazio de dado de referência — POST /pets falha com
-- ORA-02291 (FK_PET_RACA) e POST de evento clínico falha por falta de
-- TIPO_EVENTO. MEDICAMENTO não é semeado em profile nenhum, mesmo tendo CRUD
-- real no .NET (MedicamentosController) — incluído aqui por consistência com
-- o objetivo da task (compose funcional do zero, sem intervenção manual).
--
-- ESCOPO: catálogo puro. Nenhum dado fictício de demonstração (CLINICA,
-- TUTOR, VETERINARIO, PET, AGENDAMENTO) — isso continua exclusivo do
-- callback de dev (afterMigrate__seeds_dev.sql), que não roda em prod.
--
-- IDEMPOTÊNCIA: MERGE ... WHEN NOT MATCHED, mesmo padrão do callback de dev.
-- Aplicar duas vezes (ou contra um banco que já tem os dados) não duplica.
--
-- COEXISTÊNCIA COM O PROFILE DEV: os IDs de ESPECIE/RACA/TIPO_EVENTO abaixo
-- são deliberadamente os MESMOS que afterMigrate__seeds_dev.sql já usa (e com
-- o mesmo conteúdo). V14 roda primeiro (é migration, aplicada antes de
-- qualquer callback), então em dev os MERGE do callback encontram os
-- registros já inseridos por V14 (match por PK) e não fazem nada — sem
-- duplicata, sem conflito de UNIQUE (NM_ESPECIE / NM_TIPO / UK_TIPO_EVENTO_CD).
-- MEDICAMENTO não existe no callback — sem risco de colisão de ID.
-- =============================================================================

-- ─── 1. ESPECIE ─────────────────────────────────────────────────────────────
MERGE INTO ESPECIE t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_ESPECIE = 1)
WHEN NOT MATCHED THEN INSERT (ID_ESPECIE, NM_ESPECIE)
VALUES (1, 'Cao');

MERGE INTO ESPECIE t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_ESPECIE = 2)
WHEN NOT MATCHED THEN INSERT (ID_ESPECIE, NM_ESPECIE)
VALUES (2, 'Gato');

-- ─── 2. TIPO_EVENTO ─────────────────────────────────────────────────────────
-- CD_TIPO (V9): chave de negócio usada pelo .NET — igual a NM_TIPO.
MERGE INTO TIPO_EVENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_TIPO_EVENTO = 1)
WHEN NOT MATCHED THEN INSERT (ID_TIPO_EVENTO, CD_TIPO, NM_TIPO, DS_TIPO, ST_ATIVO)
VALUES (1, 'CONSULTA', 'CONSULTA', 'Consulta veterinária presencial', 'S');

MERGE INTO TIPO_EVENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_TIPO_EVENTO = 2)
WHEN NOT MATCHED THEN INSERT (ID_TIPO_EVENTO, CD_TIPO, NM_TIPO, DS_TIPO, ST_ATIVO)
VALUES (2, 'TELEORIENTACAO', 'TELEORIENTACAO', 'Orientação veterinária via videochamada', 'S');

MERGE INTO TIPO_EVENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_TIPO_EVENTO = 3)
WHEN NOT MATCHED THEN INSERT (ID_TIPO_EVENTO, CD_TIPO, NM_TIPO, DS_TIPO, ST_ATIVO)
VALUES (3, 'VACINA', 'VACINA', 'Aplicação de vacina', 'S');

MERGE INTO TIPO_EVENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_TIPO_EVENTO = 4)
WHEN NOT MATCHED THEN INSERT (ID_TIPO_EVENTO, CD_TIPO, NM_TIPO, DS_TIPO, ST_ATIVO)
VALUES (4, 'PRESCRICAO', 'PRESCRICAO', 'Prescrição de medicamento', 'S');

MERGE INTO TIPO_EVENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_TIPO_EVENTO = 5)
WHEN NOT MATCHED THEN INSERT (ID_TIPO_EVENTO, CD_TIPO, NM_TIPO, DS_TIPO, ST_ATIVO)
VALUES (5, 'EXAME', 'EXAME', 'Exame laboratorial ou de imagem', 'S');

-- ─── 3. RACA ────────────────────────────────────────────────────────────────
MERGE INTO RACA t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_RACA = 1)
WHEN NOT MATCHED THEN INSERT (ID_RACA, ID_ESPECIE, NM_RACA, DS_PREDISPOSICAO)
VALUES (1, 1, 'Labrador', 'Predisposição a displasia coxofemoral e obesidade.');

MERGE INTO RACA t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_RACA = 2)
WHEN NOT MATCHED THEN INSERT (ID_RACA, ID_ESPECIE, NM_RACA, DS_PREDISPOSICAO)
VALUES (2, 1, 'Poodle', 'Predisposição a problemas dentários e otite.');

MERGE INTO RACA t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_RACA = 3)
WHEN NOT MATCHED THEN INSERT (ID_RACA, ID_ESPECIE, NM_RACA, DS_PREDISPOSICAO)
VALUES (3, 2, 'Siames', 'Predisposição a problemas renais e respiratórios.');

MERGE INTO RACA t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_RACA = 4)
WHEN NOT MATCHED THEN INSERT (ID_RACA, ID_ESPECIE, NM_RACA, DS_PREDISPOSICAO)
VALUES (4, 2, 'SRD-felino', 'Sem raça definida — felino. Boa resistência geral.');

-- ─── 4. MEDICAMENTO ─────────────────────────────────────────────────────────
-- Não semeado em nenhum profile hoje (nem pelo callback de dev). Catálogo
-- mínimo para permitir POST /eventos-clinicos/prescricoes sem carga manual.
MERGE INTO MEDICAMENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_MEDICAMENTO = 1)
WHEN NOT MATCHED THEN INSERT (ID_MEDICAMENTO, NM_MEDICAMENTO, DS_PRINCIPIO_ATIVO, DS_APRESENTACAO)
VALUES (1, 'Amoxicilina', 'Amoxicilina tri-hidratada', 'Comprimido 500mg');

MERGE INTO MEDICAMENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_MEDICAMENTO = 2)
WHEN NOT MATCHED THEN INSERT (ID_MEDICAMENTO, NM_MEDICAMENTO, DS_PRINCIPIO_ATIVO, DS_APRESENTACAO)
VALUES (2, 'Meloxicam', 'Meloxicam', 'Suspensão oral 1,5mg/mL');

MERGE INTO MEDICAMENTO t
USING (SELECT 1 FROM DUAL) SRC ON (t.ID_MEDICAMENTO = 3)
WHEN NOT MATCHED THEN INSERT (ID_MEDICAMENTO, NM_MEDICAMENTO, DS_PRINCIPIO_ATIVO, DS_APRESENTACAO)
VALUES (3, 'Ivermectina', 'Ivermectina', 'Solução injetável 1%');
