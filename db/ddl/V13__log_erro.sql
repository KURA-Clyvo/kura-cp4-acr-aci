-- =============================================================================
-- V13__log_erro.sql
-- TASK-26 (parte 1/2, DB-01). Recria LOG_ERRO — hoje só existe no bootstrap
-- DevOps-Cloud/db/init/01_schema.sql, que está sendo aposentado (parte 2/2
-- da TASK-26). Um Oracle criado só por Flyway V1→V12 não tem essa tabela.
--
-- Objeto de banco da rubrica FIAP (disciplina BD — log de erro de procedures
-- PL/SQL, ver banco/kura_req1_procedures_carga.sql e banco/relatorio_banco_de_dados.md).
--
-- CORREÇÃO AO BRIEF: a task-26-logerro-brief.md presumia "nenhum código de
-- aplicação escreve em LOG_ERRO", citando só o ExceptionHandlerMiddleware.cs
-- do .NET (que de fato não escreve — comentário explícito no próprio arquivo).
-- Investigação (grep completo em .NET/Java/Luna) encontrou uma exceção real:
-- kura-luna-ai/luna/src/db/repositories/log_erro_repo.py::LogErroRepository
-- FAZ INSERT em LOG_ERRO (fail-safe, nunca propaga exceção) e é instanciado em
-- luna/src/web/dependencies.py, usado por notification_service.py e
-- inbound_message_service.py — não é código morto. O INSERT do Luna informa
-- SEQ_LOG_ERRO.NEXTVAL explicitamente (não depende do DEFAULT da coluna) e
-- usa exatamente as colunas abaixo (ID_LOG, NM_PROCEDURE, NM_USUARIO,
-- NR_CODIGO_ERRO, DS_MENSAGEM_ERRO, DS_PARAMETROS, DS_STACK_TRACE) — o shape
-- desta migration já é compatível. Não é um gap desta task (Luna não é o
-- repo de trabalho aqui), mas fica registrado para quem fechar a parte 2/2.
--
-- Java continua sem gravar nela — não criar LogErroRepository/entidade JPA
-- aqui (fora de escopo, não pedido).
--
-- Arquivo único e portável (sem split -h2/-oracle): diferente da V12, onde
-- H2 rejeitava `ALTER TABLE ... MODIFY (col DROP IDENTITY)`, aqui H2 em
-- MODE=Oracle aceita `NUMBER(15) DEFAULT SEQ_LOG_ERRO.NEXTVAL NOT NULL`
-- dentro de um CREATE TABLE sem ajuste — validado manualmente via
-- org.h2.tools.RunScript (h2 2.2.224, MODE=Oracle) antes de escrever este
-- arquivo. VARCHAR2/CLOB/COMMENT ON TABLE/CREATE INDEX ... DESC também já
-- são usados sem split em V1/V9/V11 (db/migration/) — mesmo H2 Oracle mode.
--
-- SEQ_LOG_ERRO START WITH 100 — mesma convenção da V1/V12 (acima do maior ID
-- de seeds de dev). Bootstrap original (DevOps-Cloud/db/init/01_schema.sql)
-- usava START WITH 1; diverge de propósito para não colidir com nada.
--
-- Fora de escopo (decisão já travada em E-11/TASK-26, ver brief): não recriar
-- VW_TIMELINE_CLINICA nem as 2 sequences extras do bootstrap — sem consumidor
-- em nenhum repo.
-- =============================================================================

CREATE SEQUENCE SEQ_LOG_ERRO START WITH 100 INCREMENT BY 1;

CREATE TABLE LOG_ERRO (
    ID_LOG            NUMBER(15)     DEFAULT SEQ_LOG_ERRO.NEXTVAL NOT NULL,
    NM_PROCEDURE      VARCHAR2(120)  NOT NULL,
    NM_USUARIO        VARCHAR2(60)   NOT NULL,
    DT_ERRO           TIMESTAMP      DEFAULT SYSTIMESTAMP NOT NULL,
    NR_CODIGO_ERRO    NUMBER(10)     NOT NULL,
    DS_MENSAGEM_ERRO  VARCHAR2(2000) NOT NULL,
    DS_PARAMETROS     VARCHAR2(2000),
    DS_STACK_TRACE    CLOB,
    CONSTRAINT PK_LOG_ERRO PRIMARY KEY (ID_LOG)
);

CREATE INDEX IDX_LOG_DATA ON LOG_ERRO(DT_ERRO DESC);
CREATE INDEX IDX_LOG_PROCEDURE ON LOG_ERRO(NM_PROCEDURE);

COMMENT ON TABLE LOG_ERRO IS 'Log de erros de procedures Oracle (requisito FIAP — disciplina BD).';
