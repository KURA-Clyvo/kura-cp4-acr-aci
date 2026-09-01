-- =============================================================================
-- V16__interacao_canal_clinica_nullable.sql
-- TASK-76 (KURA_BACKLOG_FIX_7). Torna INTERACAO_CANAL.ID_CLINICA nullable.
--
-- Decisao do Felipe: a interacao de WhatsApp com tutor desconhecido passa a
-- ser GRAVADA (ID_CLINICA nulo) em vez de rejeitada com 422. Hoje
-- LunaService.cs:90-93 (.NET, TASK-77, cadeia bloqueada por esta migration)
-- rejeita o INSERT quando o tutor nao foi encontrado, e o resultado e:
-- nenhuma linha em INTERACAO_CANAL e um erro FALSO em LOG_ERRO (nao houve
-- erro de verdade, so um tutor desconhecido).
--
-- Consequencia aceita: uma linha com ID_CLINICA nulo e invisivel para
-- qualquer consulta escopada por clinica -- o filtro de tenant do .NET
-- (IClinicaContext / ApplyTenantFilters) nunca vai casa-la, porque compara
-- IdClinica = @filtro e NULL nunca satisfaz igualdade. O ganho e auditoria
-- (a mensagem existe, fica rastreavel) e parar o erro falso em LOG_ERRO --
-- nao e visibilidade no app da clinica.
--
-- Teste empirico feito nesta task: o H2 deste projeto roda com MODE=Oracle
-- (application-dev.yml, jdbc:h2:mem:kuradb;...;MODE=Oracle), e a V9 ja prova
-- que "ALTER TABLE t MODIFY col NOT NULL" e portavel entre H2 (MODE=Oracle) e
-- Oracle real sem split (V9__schema_drift_clinico.sql:42). Se a suite
-- "./mvnw test -Dspring.profiles.active=dev" (que roda Flyway com as
-- migrations -h2) continuar verde com este arquivo unico em db/migration/,
-- fica provado que "MODIFY col NULL" (o inverso) tambem e portavel, e o
-- split -oracle/-h2 nao se justifica -- ver decisao final no relatorio.
-- =============================================================================

ALTER TABLE INTERACAO_CANAL MODIFY ID_CLINICA NULL;

COMMENT ON COLUMN INTERACAO_CANAL.ID_CLINICA IS 'Nullable desde V16 (TASK-76): NULL indica interacao de canal cuja origem nao foi identificada (tutor nao cadastrado no telefone recebido) -- gravada para auditoria, mas invisivel a qualquer consulta escopada por clinica (o filtro de tenant nunca casa NULL).';
