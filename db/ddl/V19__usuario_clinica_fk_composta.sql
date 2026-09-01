-- =============================================================================
-- V19__usuario_clinica_fk_composta.sql
-- FD-14 (KURA_BACKLOG_FIN_DOTNET). Fecha um furo de multi-tenancy NO BANCO:
-- USUARIO_CLINICA da clinica A podia apontar um VETERINARIO da clinica B.
--
-- O FURO, MEDIDO CONTRA ORACLE REAL (nao deduzido do DDL)
-- A V17 declarou FK_USUARIO_CLINICA_VET como FOREIGN KEY (ID_VETERINARIO)
-- REFERENCES VETERINARIO(ID_VETERINARIO) -- ou seja, a FK garante que o
-- veterinario EXISTE, e nao que ele pertence a MESMA clinica do usuario.
-- Medicao feita contra o Oracle do compose:
--   INSERT USUARIO_CLINICA(ID_CLINICA=100, ID_VETERINARIO=101) com o vet 101
--   pertencendo a clinica 101  -> ACEITO (o furo).
-- Controle positivo da mesma medicao (sem ele, "aceito" nao distingue "FK
-- fraca" de "FK inexistente"):
--   o mesmo INSERT com ID_VETERINARIO inexistente -> ORA-02291.
-- Conclusao: a FK existe e morde; ela e do ESCOPO ERRADO.
--
-- POR QUE ISTO VIRA MIGRATION E NAO FICA SO EM CODIGO (ruling do Felipe: PAGAR)
-- Hoje a unica defesa e uma checagem em C# no .NET (travada por 2 testes desde
-- a FD-03). O schema Oracle e COMPARTILHADO por dois backends que evoluem
-- separados, e o backend Java escreve na mesma base sem passar por essa
-- checagem. Defesa que existe so em codigo de um dos lados nao e defesa em
-- profundidade -- e uma convencao. Esta migration move o invariante para o
-- unico lugar que os dois backends obrigatoriamente respeitam.
--
-- POR QUE SAO 2 PASSOS E NAO UM ALTER SO
-- O Oracle (e o H2) exigem que o alvo de uma FK seja PK ou UNIQUE.
-- VETERINARIO (tabela da V1) tem PK em (ID_VETERINARIO) e UNIQUE em (NR_CRMV);
-- nao existe chave unica em (ID_CLINICA, ID_VETERINARIO). Entao:
--   1. cria-se UK_VET_CLINICA_ID -- chave REDUNDANTE cujo unico proposito e
--      ser alvo de FK;
--   2. troca-se FK_USUARIO_CLINICA_VET pela versao composta.
--
-- A UK NOVA NAO PODE FALHAR POR DADO PRE-EXISTENTE -- E ISSO E ESTRUTURAL,
-- NAO SORTE. A preocupacao legitima ("linha existente que viole a UK nova faz
-- a migration falhar na aplicacao") foi medida contra o Oracle real ANTES de
-- escrever este arquivo: ID_VETERINARIO ja e PK de VETERINARIO
-- (constraint SYS_C008340, tipo P). Uma PK ja garante unicidade de
-- ID_VETERINARIO sozinho, logo o par (ID_CLINICA, ID_VETERINARIO) e unico POR
-- IMPLICACAO -- nao existe dataset possivel que viole a UK nova sem ja violar
-- a PK. Constraints medidas em VETERINARIO no momento desta task:
-- SYS_C008340 (P), UK_VET_CRMV (U), FK_VET_CLINICA (R).
-- (Isso dispensa a caca a linhas violadoras DA UK -- e SO da UK. NAO dispensa
-- a prova V1->V19 do zero, que foi executada -- ver fd-14-report.md.)
--
-- ATENCAO: O PASSO 2 *PODE* FALHAR POR DADO PRE-EXISTENTE -- LEIA ANTES DE
-- APLICAR ESTA MIGRATION EM BASE COM DADO ACUMULADO.
-- O argumento estrutural acima vale para o passo 1 (a UK) e NAO se estende ao
-- passo 2. Se a base ja contiver UMA UNICA linha USUARIO_CLINICA apontando
-- veterinario de outra clinica -- exatamente o furo que esta migration fecha,
-- e que era ACEITO ate agora --, o ADD CONSTRAINT do passo 2 falha com
--   ORA-02298: cannot validate (RM562999.FK_USUARIO_CLINICA_VET)
--               - parent keys not found
-- e o Flyway aborta, o que impede o kura-tutor de subir.
-- PIOR: DDL no Oracle autocommita e o DROP vem ANTES do ADD, entao quando o
-- passo 2 falha a tabela fica SEM FK NENHUMA -- estritamente pior que o estado
-- anterior a migration. Ambos MEDIDOS (maestro e revisao G2 da FD-14, por
-- caminhos independentes).
-- VERIFICACAO OBRIGATORIA antes de aplicar em base com dado -- e rode o
-- CONTROLE POSITIVO dela (plante uma linha cross-tenant e confirme que a
-- consulta devolve 1), porque um 0 de detector nao provado nao vale nada:
--   SELECT COUNT(*) FROM USUARIO_CLINICA u
--    WHERE u.ID_VETERINARIO IS NOT NULL
--      AND NOT EXISTS (SELECT 1 FROM VETERINARIO v
--                       WHERE v.ID_VETERINARIO = u.ID_VETERINARIO
--                         AND v.ID_CLINICA     = u.ID_CLINICA);
-- Resultado > 0 => corrija as linhas ANTES de aplicar. Em base nascida do zero
-- (o compose) o resultado e 0 e o passo 2 passa.
--
-- ID_VETERINARIO CONTINUA NULLABLE, E A FK COMPOSTA CONTINUA PERMITINDO NULO
-- Um GESTOR pode nao ser veterinario (dono, administrador, financeiro) -- a V17
-- deixou ID_VETERINARIO nullable de proposito. Numa FK composta, tanto Oracle
-- quanto H2 usam semantica de nulo parcial: se QUALQUER coluna da FK for NULA,
-- a constraint NAO e verificada e a linha e aceita. Como ID_CLINICA e NOT NULL
-- em USUARIO_CLINICA, o unico caso de nulo parcial e exatamente o GESTOR sem
-- veterinario -- que continua valido. Isso esta travado por teste
-- (UsuarioClinicaV19FkCompostaTest#gestorSemVeterinarioContinuaAceito), porque
-- e a regressao mais provavel desta migration e ela NAO seria pega por
-- "o INSERT cross-tenant passou a falhar".
--
-- POR QUE ARQUIVO UNICO EM db/migration/ (SEM SPLIT -oracle/-h2)
-- O split existe quando a SINTAXE diverge entre os bancos (V15 e V17/V18
-- divergem so na expressao do DEFAULT da PK: SEQ_X.NEXTVAL x NEXT VALUE FOR
-- SEQ_X). Esta migration nao declara DEFAULT nenhum: ALTER TABLE ... ADD
-- CONSTRAINT ... UNIQUE, DROP CONSTRAINT <nome> e ADD CONSTRAINT ... FOREIGN
-- KEY (...) REFERENCES tabela(...) sao SQL padrao e identicos nos dois bancos.
-- Duplicar o arquivo aqui criaria divida de split sem ganho -- o mesmo
-- criterio da V16, que tambem e arquivo unico. O H2 executa este arquivo em
-- toda rodada da suite (dev le classpath:db/migration + db/migration-h2), e o
-- Oracle o executa no compose (prod le classpath:db/migration +
-- db/migration-oracle): as duas variantes de profile rodam ESTE mesmo arquivo.
--
-- ESCOPO NEGATIVO
-- A V17 e a V18 NAO sao alteradas -- elas ja estao aplicadas e mexer nelas
-- quebraria a validacao de checksum do Flyway (validate-on-migrate: true em
-- prod). A definicao original da FK na V17 permanece como registro historico;
-- quem ler a V17 isoladamente vai ver a FK fraca, e e por isso que este
-- cabecalho existe.
-- =============================================================================

-- Passo 1 de 2 -- chave unica redundante em VETERINARIO, cujo unico proposito e
-- ser alvo da FK composta do passo 2. Unica por implicacao da PK (ver acima).
ALTER TABLE VETERINARIO
    ADD CONSTRAINT UK_VET_CLINICA_ID UNIQUE (ID_CLINICA, ID_VETERINARIO);

COMMENT ON TABLE VETERINARIO IS 'Veterinarios vinculados a clinica -- owned pelo .NET. UK_VET_CLINICA_ID (V19) e redundante com a PK e existe apenas para ser alvo da FK composta FK_USUARIO_CLINICA_VET, que impede vinculo cross-tenant em USUARIO_CLINICA.';

-- Passo 2 de 2 -- troca a FK de escopo errado (so ID_VETERINARIO) pela composta
-- (ID_CLINICA, ID_VETERINARIO). Depois disto, USUARIO_CLINICA da clinica A
-- apontando VETERINARIO da clinica B e RECUSADO PELO BANCO (ORA-02291), nao
-- apenas pelo codigo C# do .NET.
ALTER TABLE USUARIO_CLINICA
    DROP CONSTRAINT FK_USUARIO_CLINICA_VET;

ALTER TABLE USUARIO_CLINICA
    ADD CONSTRAINT FK_USUARIO_CLINICA_VET
    FOREIGN KEY (ID_CLINICA, ID_VETERINARIO)
    REFERENCES VETERINARIO (ID_CLINICA, ID_VETERINARIO);

COMMENT ON COLUMN USUARIO_CLINICA.ID_VETERINARIO IS 'Vinculo explicito com o registro de VETERINARIO, quando o usuario for veterinario. NULL para GESTOR que nao atende. Desde a V19 a FK e COMPOSTA com ID_CLINICA: o banco recusa vinculo com veterinario de outra clinica. Nulo parcial (GESTOR sem vet) continua aceito por semantica de FK composta.';
