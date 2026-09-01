-- =============================================================================
-- V17__usuario_clinica.sql (variante Oracle)
-- FD-01 (KURA_BACKLOG_FIN_DOTNET). Cria USUARIO_CLINICA, tabela .NET-owned que
-- introduz IDENTIDADE INDIVIDUAL no lado clínico.
--
-- POR QUE ESTA TABELA EXISTE
-- Hoje o login do app da clínica é POR CLÍNICA, não por pessoa: o .NET valida
-- e-mail/senha contra CLINICA.DS_EMAIL_ACESSO / CLINICA.DS_SENHA_HASH
-- (AuthService.cs:34-59), e o veterinário "logado" é escolhido por uma
-- heurística de fallback — não por quem digitou a senha. Consequências
-- diretas: (1) não existe autoria confiável de nenhum ato clínico ou
-- financeiro, porque toda ação nasce do mesmo par e-mail/senha compartilhado
-- pela clínica inteira; (2) não existe papel — não há como distinguir quem
-- pode ver faturamento de quem só atende. O ciclo financeiro depende dessa
-- distinção, e por isso identidade vem ANTES do financeiro e o bloqueia.
--
-- USUARIO_CLINICA é a linha por humano que falta: cada pessoa da clínica tem
-- e-mail e hash próprios, um papel (TP_PERFIL) e, quando for o caso, o vínculo
-- com o registro de VETERINARIO que já existe.
--
-- ID_VETERINARIO É NULLABLE DE PROPÓSITO
-- Um GESTOR pode não ser veterinário (dono, administrador, financeiro). O
-- vínculo, quando existe, é explícito — não derivado. Este arquivo NÃO tenta
-- adivinhar o vínculo por e-mail na conversão abaixo: casar
-- CLINICA.DS_EMAIL_ACESSO com VETERINARIO.DS_EMAIL seria exatamente a mesma
-- classe de heurística de fallback que este ciclo está eliminando, e ela
-- produziria autoria ERRADA (não ausente), que é estritamente pior.
--
-- ESCOPO NEGATIVO DESTA MIGRATION
-- CLINICA.DS_EMAIL_ACESSO e CLINICA.DS_SENHA_HASH NÃO são removidas aqui. A
-- remoção só é segura depois que a FD-03 provar que nenhum caminho de código
-- ainda lê essas colunas; enquanto o .NET autenticar por elas, derrubá-las
-- derrubaria o login. Elas continuam sendo a FONTE da conversão abaixo.
--
-- PK POR SEQUENCE, NÃO IDENTITY
-- Esta tabela é .NET-owned (quem escreve nela é o backend .NET, FD-02/FD-03), e
-- o padrão .NET-owned deste projeto é DEFAULT SEQ_x.NEXTVAL (ver V12 e
-- docs/V12-pk-strategy-map.md). IDENTITY é o padrão Java-owned — a V9 usou
-- IDENTITY em 11 tabelas .NET-owned por engano e isso custou a V12 inteira para
-- reverter (ORA-02289 em toda base que não fosse bootstrapada manualmente).
-- Não repetir o erro aqui.
--
-- POR QUE HÁ SPLIT -oracle/-h2 — E O QUE FOI, DE FATO, MEDIDO
-- ⚠️ CORREÇÃO DA REVISÃO G2. A primeira versão deste cabeçalho repetia a frase
-- herdada do cabeçalho da V15: "o H2 não aceita SEQ_X.NEXTVAL em expressão de
-- DEFAULT nem sob MODE=Oracle". Essa frase é FALSA, e nunca tinha sido
-- executada por ninguém neste projeto. Medição própria, feita nesta task,
-- contra o mesmo H2 da suíte (2.2.224, MODE=Oracle): o H2 ACEITA
-- `DEFAULT SEQ_X.NEXTVAL`, cria a tabela e a sequence alimenta a PK. Isso está
-- travado em teste — UsuarioClinicaV17MigrationTest
-- #h2AceitaNextvalEmExpressaoDeDefault, que mede em vez de citar.
-- (A V15 carrega a MESMA frase falsa. Corrigi-la está fora do escopo da FD-01
-- e NÃO foi feito aqui — quem for mexer nela precisa saber disso.)
--
-- O QUE **NÃO** FOI MEDIDO: se o Oracle aceita `DEFAULT NEXT VALUE FOR SEQ_X`.
-- Nenhum teste desta suíte toca Oracle — a conta da FIAP está bloqueada
-- (ORA-28000) e este ciclo não abre conexão com ela. Ou seja: das duas metades
-- do argumento de portabilidade, uma foi medida e REFUTADA, e a outra continua
-- NÃO VERIFICADA. Não troque uma alegação não medida por outra: o que está
-- escrito aqui é o que rodou.
--
-- POR QUE O SPLIT FICA MESMO ASSIM: colapsar os dois arquivos em um exige
-- eleger UMA sintaxe para rodar nos dois bancos, e a única metade verificada é
-- a do H2 aceitando a sintaxe Oracle. Unificar seria, então, uma aposta sobre o
-- banco de PRODUÇÃO validada só pelo banco de teste — e o custo assimétrico é
-- claro: o split custa duplicação de arquivo; unificar errado custa o startup
-- do prod. Além disso, unificar aqui abriria precedente contra a V12 e a V15,
-- que é mudança de raio maior que a FD-01. O split fica, e a justificativa
-- honesta é: ele se sustenta pelo lado NÃO MEDIDO, não pelo lado medido.
--
-- Todo o RESTO do DDL desta migration foi verificado como portável e é
-- IDÊNTICO nas duas variantes: tipos (NUMBER/VARCHAR2/CHAR/TIMESTAMP), CHECK,
-- UNIQUE, FK, COMMENT e o INSERT ... SELECT da conversão. A única linha que
-- diverge entre os dois arquivos é a do DEFAULT da PK — e isso está travado por
-- teste (UsuarioClinicaV17MigrationTest#variantesDiferemApenasNaLinhaDoDefaultDaPk),
-- para que o split não vire dívida silenciosa se alguém editar um lado só. A
-- comparação normaliza CRLF/LF de propósito (o repo tem core.autocrlf=true e
-- nenhum .gitattributes): o alvo é divergência SEMÂNTICA, não fim de linha.
--
-- UNICIDADE DE E-MAIL: POR CLÍNICA, NÃO GLOBAL
-- UK_USUARIO_CLINICA_EMAIL é (ID_CLINICA, DS_EMAIL) — deliberadamente
-- diferente da UK_CLINICA_EMAIL_ACESSO da V1, que é global sobre uma coluna
-- só. Duas pessoas de clínicas diferentes podem usar o mesmo e-mail (um
-- veterinário que atende em duas clínicas é o caso real); duas pessoas da
-- MESMA clínica não podem. Consequência para a FD-03: o login não pode
-- resolver o usuário só pelo e-mail — precisa do par (clínica, e-mail) ou de
-- um desempate explícito.
--
-- TP_PERFIL E O CUSTO DE ACRESCENTAR UM PAPEL
-- CHK_USUARIO_CLINICA_PERFIL é uma constraint NOMEADA, de propósito único, que
-- não compartilha expressão com nenhuma outra coluna. Acrescentar
-- 'RECEPCIONISTA' depois é mexer nessa constraint e em nada mais:
--   ALTER TABLE USUARIO_CLINICA DROP CONSTRAINT CHK_USUARIO_CLINICA_PERFIL;
--   ALTER TABLE USUARIO_CLINICA ADD CONSTRAINT CHK_USUARIO_CLINICA_PERFIL
--       CHECK (TP_PERFIL IN ('GESTOR','VETERINARIO','RECEPCIONISTA'));
-- (São 2 statements porque nem Oracle nem H2 sabem reescrever a expressão de
-- um CHECK in-place — `MODIFY CONSTRAINT` só muda estado, não expressão. Não
-- vamos alegar "uma linha" quando são duas; o que a task realmente pede está
-- garantido: nenhum outro objeto do schema precisa ser tocado.) VARCHAR2(20)
-- dimensiona o campo para 'RECEPCIONISTA' (13) e sucessores sem ALTER de tipo.
--
-- DIMENSÕES DE DS_EMAIL / DS_SENHA_HASH
-- Copiadas de CLINICA.DS_EMAIL_ACESSO VARCHAR2(120) e CLINICA.DS_SENHA_HASH
-- VARCHAR2(256) (V1). Paridade exata é requisito da conversão: coluna destino
-- menor que a origem truncaria o hash em silêncio — e um hash BCrypt truncado
-- não falha o INSERT, falha o LOGIN, muito depois, sem rastro. O hash real de
-- BCrypt tem 60 caracteres; os 256 são folga herdada, mantida por paridade.
-- =============================================================================

CREATE SEQUENCE SEQ_USUARIO_CLINICA START WITH 100 INCREMENT BY 1;

CREATE TABLE USUARIO_CLINICA (
    ID_USUARIO_CLINICA NUMBER(10)    DEFAULT SEQ_USUARIO_CLINICA.NEXTVAL PRIMARY KEY,
    ID_CLINICA         NUMBER(10)    NOT NULL,
    ID_VETERINARIO     NUMBER(10),
    DS_EMAIL           VARCHAR2(120) NOT NULL,
    DS_SENHA_HASH      VARCHAR2(256) NOT NULL,
    TP_PERFIL          VARCHAR2(20)  NOT NULL,
    ST_ATIVA           CHAR(1)       DEFAULT 'S' NOT NULL,
    DT_CRIACAO         TIMESTAMP     DEFAULT CURRENT_TIMESTAMP NOT NULL,
    DT_ATUALIZACAO     TIMESTAMP,
    CONSTRAINT FK_USUARIO_CLINICA_CLINICA FOREIGN KEY (ID_CLINICA)     REFERENCES CLINICA(ID_CLINICA),
    CONSTRAINT FK_USUARIO_CLINICA_VET     FOREIGN KEY (ID_VETERINARIO) REFERENCES VETERINARIO(ID_VETERINARIO),
    CONSTRAINT UK_USUARIO_CLINICA_EMAIL   UNIQUE (ID_CLINICA, DS_EMAIL),
    CONSTRAINT CHK_USUARIO_CLINICA_PERFIL CHECK (TP_PERFIL IN ('GESTOR','VETERINARIO')),
    CONSTRAINT CHK_USUARIO_CLINICA_ATIVA  CHECK (ST_ATIVA  IN ('S','N'))
);

COMMENT ON TABLE  USUARIO_CLINICA                    IS '.NET owned. Identidade individual do lado clinico: uma linha por humano da clinica (login proprio + papel), substituindo o login por clinica de CLINICA.DS_EMAIL_ACESSO.';
COMMENT ON COLUMN USUARIO_CLINICA.ID_CLINICA         IS 'Clinica a que o usuario pertence. NOT NULL: nao existe usuario sem tenant -- e a chave do isolamento multi-tenant do .NET.';
COMMENT ON COLUMN USUARIO_CLINICA.ID_VETERINARIO     IS 'Vinculo explicito com o registro de VETERINARIO, quando o usuario for veterinario. NULL para GESTOR que nao atende. Nunca derivado por heuristica.';
COMMENT ON COLUMN USUARIO_CLINICA.DS_EMAIL           IS 'E-mail de login. Unico POR CLINICA (UK_USUARIO_CLINICA_EMAIL), nao globalmente -- a mesma pessoa pode existir em duas clinicas.';
COMMENT ON COLUMN USUARIO_CLINICA.DS_SENHA_HASH      IS 'Hash BCrypt da senha individual. Dimensao em paridade com CLINICA.DS_SENHA_HASH para a conversao da V17 nao truncar.';
COMMENT ON COLUMN USUARIO_CLINICA.TP_PERFIL          IS 'Papel: GESTOR ou VETERINARIO (CHK_USUARIO_CLINICA_PERFIL). Constraint nomeada e de proposito unico para que acrescentar papel futuro (ex.: RECEPCIONISTA) toque so ela.';
COMMENT ON COLUMN USUARIO_CLINICA.ST_ATIVA           IS 'Soft delete no padrao do projeto (S/N). DELETE fisico nunca acontece.';

-- -----------------------------------------------------------------------------
-- CONVERSÃO DO DADO EXISTENTE (ruling D-10)
--
-- Cria, para cada CLINICA que HOJE tem credencial de acesso, um usuário GESTOR
-- com o MESMO e-mail e o MESMO hash — de modo que quem consegue entrar hoje
-- continue conseguindo entrar depois que a FD-03 trocar a fonte da autenticação.
-- Reaproveitar o hash (em vez de gerar senha nova) é o que torna a virada
-- invisível para o usuário final: BCrypt valida a mesma senha contra o mesmo
-- hash, independentemente de qual tabela o guarda.
--
-- ID_VETERINARIO fica NULL — ver a seção "ID_VETERINARIO É NULLABLE DE
-- PROPÓSITO" no cabeçalho: adivinhar o vínculo aqui produziria autoria errada.
--
-- ⚠️ QUANTAS LINHAS ISSO CONVERTE EM AMBIENTE DO ZERO: ZERO, e isso é por
-- construção, não defeito. Os 3 produtores de CLINICA.DS_EMAIL_ACESSO foram
-- medidos: o callback de seed do profile dev não escreve a coluna, e os outros
-- dois (AuthService.RegisterClinicaAsync no .NET e DevOps-Cloud/scripts/
-- seed-demo.sh, que chama o primeiro) rodam em RUNTIME, depois de toda
-- migration. Num `docker compose down -v && up -d` o schema nasce vazio e este
-- INSERT converte nada. Ele existe para a base JÁ EXISTENTE (o Oracle da FIAP
-- tem dado). O par que falta — criar o USUARIO_CLINICA no momento em que uma
-- clínica é registrada em runtime — é responsabilidade da FD-03, não desta
-- migration.
--
-- WHERE DS_SENHA_HASH IS NOT NULL: USUARIO_CLINICA.DS_SENHA_HASH é NOT NULL, e
-- uma clínica com e-mail mas sem hash não consegue logar hoje de qualquer
-- forma — converter essa linha só trocaria "não loga" por "migration falha".
-- (Em Oracle e em H2 sob MODE=Oracle, string vazia É NULL, então o mesmo
-- predicado cobre DS_EMAIL_ACESSO='' sem cláusula extra.)
--
-- NOT EXISTS: guarda de idempotência contra UK_USUARIO_CLINICA_EMAIL. A
-- migration roda uma vez por definição, mas uma base que já tenha o usuário
-- (criado à mão, ou por um replay de baseline em schema compartilhado com o
-- .NET) não pode fazer o Flyway abortar o startup inteiro.
--
-- ST_ATIVA herda c.ST_ATIVA em vez de assumir 'S': converter a credencial de
-- uma clínica DESATIVADA num usuário ATIVO criaria um acesso que hoje não
-- existe. A conversão preserva o estado, não o promove.
--
-- Os marcadores >>> / <<< abaixo são lidos por
-- UsuarioClinicaV17MigrationTest, que extrai este bloco do arquivo e o executa
-- contra dado plantado. NÃO renomeie nem remova os marcadores — o teste passa a
-- não achar o bloco e a prova de conversão morre.
-- -----------------------------------------------------------------------------
-- >>> BEGIN CONVERSAO_D10
INSERT INTO USUARIO_CLINICA (ID_CLINICA, ID_VETERINARIO, DS_EMAIL, DS_SENHA_HASH, TP_PERFIL, ST_ATIVA)
SELECT c.ID_CLINICA,
       NULL,
       c.DS_EMAIL_ACESSO,
       c.DS_SENHA_HASH,
       'GESTOR',
       c.ST_ATIVA
  FROM CLINICA c
 WHERE c.DS_EMAIL_ACESSO IS NOT NULL
   AND c.DS_SENHA_HASH   IS NOT NULL
   AND NOT EXISTS (SELECT 1
                     FROM USUARIO_CLINICA u
                    WHERE u.ID_CLINICA = c.ID_CLINICA
                      AND u.DS_EMAIL   = c.DS_EMAIL_ACESSO);
-- <<< END CONVERSAO_D10
