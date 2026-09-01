-- =============================================================================
-- V15__interacao_canal.sql (variante Oracle)
-- TASK-66 (KURA_BACKLOG_FIX_6). Cria INTERACAO_CANAL, tabela .NET-owned que
-- falta no schema — a Luna (kura-luna-ai) chama a rota canônica
-- POST /api/v1/luna/interactions hoje e recebe 404, porque o endpoint nunca
-- foi implementado e a tabela em que ele escreveria não existe (grep -rn
-- "INTERACAO" nas migrations devolvia 0 resultados antes desta migration).
-- Consequência em produção: toda mensagem de WhatsApp inbound morre
-- silenciosamente — a exceção sobe pro `except Exception` genérico do lado
-- Luna, o tutor recebe um fallback e nada é persistido nem chega ao lado
-- clínico.
--
-- Esta task entrega SOMENTE o DDL. A implementação do endpoint .NET
-- (POST /api/v1/luna/interactions, deriva ID_CLINICA do tutor, faz o INSERT)
-- é a TASK-67, que depende deste schema.
--
-- Colunas derivadas literalmente de InteractionRequestDTO
-- (kura-luna-ai/luna/src/integration/dtos.py:29-37), mais ID_CLINICA — que a
-- Luna não envia (fica a cargo do .NET derivar do tutor na TASK-67), pelo
-- mesmo motivo de TRIAGEM_LUNA.ID_CLINICA existir: multi-tenancy.
--
--   class InteractionRequestDTO(BaseModel):
--       id_tutor: int | None
--       ds_canal: Literal["WHATSAPP", "EMAIL", "SMS"]
--       ds_direcao: Literal["INBOUND", "OUTBOUND"]
--       ds_conteudo: str
--       dt_recebimento: datetime
--       ds_metadados: dict | None = None
--
-- ROTA CANÔNICA: POST /api/v1/luna/interactions (com /v1) — mesmo prefixo já
-- usado pela tabela irmã TRIAGEM_LUNA (V9: "POST /api/v1/luna/triage").
-- Nota histórica, não normativa: o cliente HTTP real da Luna hoje
-- (kura-luna-ai/luna/src/integration/kura_client.py:83-97, método
-- registrar_interacao) chama "POST /api/luna/interactions", SEM /v1 — esse é
-- o defeito 2 do Bloco 0 deste backlog (KURA_BACKLOG_FIX_6), e a TASK-68
-- corrige o client para bater com a rota canônica. Ou seja: a ausência do
-- /v1 no client é o estado quebrado transitório, não o contrato — o
-- COMMENT ON TABLE abaixo documenta a rota com /v1 de propósito, para não
-- induzir a TASK-67 (que implementa o endpoint .NET a partir deste schema) a
-- nascer no path errado.
--
-- PK por sequence, não IDENTITY: esta tabela é .NET-owned (quem escreve nela
-- é o backend .NET, TASK-67), e o padrão .NET-owned deste projeto é
-- DEFAULT SEQ_x.NEXTVAL (ver V12/docs/V12-pk-strategy-map.md). IDENTITY é o
-- padrão Java-owned — a V9 usou IDENTITY em 11 tabelas .NET-owned por engano
-- e isso custou a V12 inteira para reverter (ORA-02289 em toda base que não
-- fosse bootstrapada manualmente). Não repetir o erro aqui.
--
-- Por que este arquivo mora em db/migration-oracle/ (com variante irmã
-- idêntica em efeito, sintaxe diferente, em db/migration-h2/) e não em
-- db/migration/: a expressão de DEFAULT que lê da sequence não é portável —
-- Oracle usa `SEQ_X.NEXTVAL`, H2 usa `NEXT VALUE FOR SEQ_X` (mesmo motivo de
-- V12 — ver o comentário de cabeçalho de V12__sequences_dotnet.sql). O resto
-- da DDL (tipos NUMBER/VARCHAR2/CHAR/CLOB/TIMESTAMP, CHECK, FK, COMMENT) é
-- idêntico nas duas variantes — só a linha do DEFAULT da PK diverge.
--
-- DS_METADADOS: CLOB, não VARCHAR2(n). O DTO declara `dict | None` sem limite
-- de tamanho no contrato Python; serializar um dict arbitrário como JSON
-- pode facilmente estourar qualquer teto VARCHAR2 razoável (a Luna hoje
-- sempre envia None aqui — inbound_message_service.py não popula o campo —
-- mas o contrato existe para metadados futuros do canal, ex.: IDs de mídia
-- do WhatsApp). CLOB evita truncamento silencioso sem impor um limite
-- arbitrário que o contrato não define.
--
-- DS_CONTEUDO VARCHAR2(4000): teto máximo de VARCHAR2 no Oracle sem
-- MAX_STRING_SIZE=EXTENDED. O DTO não declara limite (`ds_conteudo: str`) e
-- mensagens de WhatsApp/Twilio cabem folgadamente dentro desse teto.
-- =============================================================================

CREATE SEQUENCE SEQ_INTERACAO_CANAL START WITH 100 INCREMENT BY 1;

CREATE TABLE INTERACAO_CANAL (
    ID_INTERACAO   NUMBER(10)     DEFAULT SEQ_INTERACAO_CANAL.NEXTVAL PRIMARY KEY,
    ID_CLINICA     NUMBER(10)     NOT NULL REFERENCES CLINICA(ID_CLINICA),
    ID_TUTOR       NUMBER(10)     REFERENCES TUTOR(ID_TUTOR),
    DS_CANAL       VARCHAR2(20)   NOT NULL,
    DS_DIRECAO     VARCHAR2(20)   NOT NULL,
    DS_CONTEUDO    VARCHAR2(4000) NOT NULL,
    DT_RECEBIMENTO TIMESTAMP      NOT NULL,
    DS_METADADOS   CLOB,
    ST_ATIVA       CHAR(1)        DEFAULT 'S' NOT NULL,
    DT_CRIACAO     TIMESTAMP DEFAULT CURRENT_TIMESTAMP NOT NULL,
    DT_ATUALIZACAO TIMESTAMP,
    CONSTRAINT CHK_INTERACAO_CANAL   CHECK (DS_CANAL   IN ('WHATSAPP','EMAIL','SMS')),
    CONSTRAINT CHK_INTERACAO_DIRECAO CHECK (DS_DIRECAO IN ('INBOUND','OUTBOUND')),
    CONSTRAINT CHK_INTERACAO_ATIVA   CHECK (ST_ATIVA   IN ('S','N'))
);
COMMENT ON TABLE INTERACAO_CANAL IS '.NET owned. Interação de canal (WhatsApp/email/SMS) registrada pela Luna via POST /api/v1/luna/interactions.';

-- TRIAGEM_LUNA é pré-existente (V9) — FK nova nasce nullable, a migration não
-- pode assumir que a tabela está vazia. TriageRequestDTO envia id_interacao,
-- ligando triagem à interação que a originou.
ALTER TABLE TRIAGEM_LUNA ADD (
    ID_INTERACAO NUMBER(10) REFERENCES INTERACAO_CANAL(ID_INTERACAO)
);
