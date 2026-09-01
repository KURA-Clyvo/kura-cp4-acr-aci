-- =============================================================================
-- V18__financeiro.sql (variante Oracle)
-- FD-07 (KURA_BACKLOG_FIN_DOTNET). Cria SERVICO_PRECO e COBRANCA, as duas
-- tabelas .NET-owned que dão base ao ciclo financeiro (FD-08..FD-11).
--
-- POR QUE ESTAS TABELAS EXISTEM
-- SERVICO_PRECO é o catálogo da clínica (ruling D-2): quanto a clínica cobra
-- por cada serviço que oferece. COBRANCA é o lançamento (ruling D-3): quanto
-- foi de fato cobrado num atendimento que aconteceu. São coisas diferentes de
-- propósito — uma é tabela de preço, a outra é histórico financeiro.
--
-- 🔴 POR QUE ID_SERVICO_PRECO É NULLABLE **E** VL_COBRADO É COLUNA PRÓPRIA
-- Esta é a razão de existir de duas decisões que parecem redundantes, e é o
-- OVERRIDE da D-2. O valor cobrado é COPIADO para VL_COBRADO no momento do
-- lançamento — NÃO é lido por FK a partir de SERVICO_PRECO.VL_PRECO. Se fosse
-- lido por FK, mudar o preço de tabela REESCREVERIA O HISTÓRICO FINANCEIRO:
-- toda cobrança passada daquele serviço passaria a valer o preço novo,
-- retroativamente, sem nenhum UPDATE em COBRANCA. Um relatório de receita de
-- um mês fechado mudaria de valor sozinho.
-- ⛔ NÃO "otimize" removendo VL_COBRADO por parecer redundante com
-- SERVICO_PRECO.VL_PRECO. A redundância é o mecanismo.
-- ID_SERVICO_PRECO é nullable pelo lado complementar da mesma ruling: um valor
-- avulso, sem serviço tabelado, é um lançamento legítimo (D-2). A FK, quando
-- preenchida, serve para o "mix por serviço" da FD-11 — é rastreabilidade de
-- ORIGEM, não fonte de valor.
--
-- POR QUE COBRANCA.ID_CLINICA EXISTE SE JÁ DÁ PARA DERIVAR DE EVENTO_CLINICO
-- Denormalização deliberada, por dois motivos concretos. (1) A FD-08 põe
-- COBRANCA no ApplyTenantFilters do .NET, e o filtro de tenant deste projeto
-- opera sobre uma coluna IdClinica da PRÓPRIA entidade — sem ela a tabela cai
-- no ponto cego estrutural que LeituraTemperatura/AlertaTemperatura já
-- ocupam (isolamento que depende de sempre passar por outra entidade, e que o
-- TenantFilterCoverageTests não consegue nem detectar). (2) Todo KPI da FD-11
-- é escopado por clínica e por período; derivar a clínica por join a cada
-- agregação é custo desnecessário no caminho mais quente do módulo.
-- ⚠️ Consequência declarada: a coluna PODE divergir de
-- EVENTO_CLINICO.ID_CLINICA se quem escreve não a derivar do evento. Manter as
-- duas coerentes é responsabilidade explícita do service da FD-10 — mesmo
-- padrão de INTERACAO_CANAL, cuja clínica é derivada do tutor no service.
--
-- CHECK DE VALOR NÃO-NEGATIVO — CONSTRAINT NOMEADA, DE PROPÓSITO ÚNICO
-- CHK_SERVICO_PRECO_VALOR e CHK_COBRANCA_VALOR travam VL_PRECO/VL_COBRADO em
-- >= 0. Isso não é zelo genérico: é o escopo negativo da FD-10 ("sem estorno")
-- escrito no schema, porque a forma natural de improvisar um estorno sem
-- migration é lançar uma cobrança negativa. Zero continua permitido (cortesia
-- é lançamento legítimo). Se estorno entrar em escopo depois, a migration que
-- o introduzir mexe nessa constraint e em nada mais — mesmo desenho da
-- CHK_USUARIO_CLINICA_PERFIL da V17.
--
-- POR QUE DT_COBRANCA É NOT NULL COM DEFAULT
-- Todo KPI da FD-11 filtra por período sobre esta coluna. Uma linha com
-- DT_COBRANCA nula é INVISÍVEL a toda consulta escopada por período — receita
-- lançada que não aparece em relatório nenhum, silenciosamente. É a mesma
-- classe de armadilha do ID_CLINICA nulo de INTERACAO_CANAL (registro que
-- existe e nenhuma consulta enxerga), e aqui não há ruling que a exija. O
-- DEFAULT CURRENT_TIMESTAMP faz o NOT NULL não custar nada a quem escreve.
--
-- POR QUE DS_FORMA_PAGAMENTO É NULLABLE E SEM CHECK
-- Nullable: exigir forma de pagamento no INSERT forçaria o veterinário a
-- escolhê-la no meio do atendimento, e o princípio de desenho da FD-10 é que o
-- dado do gestor nasce como SUBPRODUTO do fluxo do veterinário, nunca como
-- trabalho extra. Sem CHECK: uma lista fechada de formas de pagamento escrita
-- à mão aqui é inventário manual, que apodrece em silêncio (regra de ouro v7)
-- — e a validação do conjunto aceito é decisão de aplicação (FD-10), não de
-- schema. ⛔ Isto NÃO é status de processamento nem conciliação (D-1): é um
-- descritor do que o cliente usou, não o estado de uma transação.
--
-- ESCOPO NEGATIVO DESTA MIGRATION — INEGOCIÁVEL
-- D-1: nenhuma coluna de gateway, id de transação externa, status de
-- processamento ou conciliação. D-6: nenhuma coluna de imposto, repasse ou
-- margem. A receita da FD-11 se chama BRUTA justamente porque nada disso
-- existe aqui.
--
-- PK POR SEQUENCE, NÃO IDENTITY
-- As duas tabelas são .NET-owned (quem escreve nelas é o backend .NET,
-- FD-08..FD-11), e o padrão .NET-owned deste projeto é DEFAULT SEQ_x.NEXTVAL
-- (ver V12 e docs/V12-pk-strategy-map.md). IDENTITY é o padrão Java-owned — a
-- V9 usou IDENTITY em 11 tabelas .NET-owned por engano, o que fez todo INSERT
-- do .NET falhar com ORA-02289 em base criada só pelo Flyway, e custou a V12
-- inteira para reverter. Não repetir o erro aqui.
--
-- FK PARA EVENTO_CLINICO: A COLUNA É ID_EVENTO_CLINICO, A PK É ID_EVENTO
-- Armadilha de nome real, medida antes de escrever este arquivo: a PK de
-- EVENTO_CLINICO chama-se ID_EVENTO (V1:253), não ID_EVENTO_CLINICO. O
-- precedente correto está em EXAME/VACINA/PRESCRICAO da V9:
--     ID_EVENTO_CLINICO NUMBER(10) NOT NULL REFERENCES EVENTO_CLINICO(ID_EVENTO)
-- Escrever REFERENCES EVENTO_CLINICO(ID_EVENTO_CLINICO) derruba a aplicação da
-- migration. Este arquivo segue o precedente da V9.
--
-- ÍNDICES — CADA UM ARGUMENTADO, E OS RECUSADOS TAMBÉM
-- Criados (2):
--   IDX_COBRANCA_CLINICA_DATA (ID_CLINICA, DT_COBRANCA)
--     Serve ao caminho mais quente do módulo: TODO KPI da FD-11 é "por clínica
--     e por período", e a "comparação com o período anterior" faz DOIS range
--     scans com esse mesmo predicado por requisição. Ordem das colunas não é
--     arbitrária: ID_CLINICA é predicado de IGUALDADE e vem primeiro,
--     DT_COBRANCA é de FAIXA e vem depois — invertido, o índice deixa de servir
--     a busca por clínica sozinha. Como o filtro de tenant da FD-08 põe
--     ID_CLINICA = ? em toda consulta, este índice cobre também as leituras que
--     não filtram por data (prefixo à esquerda).
--   IDX_COBRANCA_EVENTO (ID_EVENTO_CLINICO)
--     Serve à leitura "cobranças deste atendimento" da FD-10, que é o acesso
--     natural a partir da tela do evento clínico. Vale por um segundo motivo,
--     independente da consulta: o Oracle NÃO cria índice automático em coluna
--     de FK, e FK filha sem índice transforma operação no pai em varredura da
--     filha para checagem de lock. Precedente direto no schema:
--     IDX_AGEND_EVENTO (V5), sobre AGENDAMENTO.ID_EVENTO_GERADO.
-- Considerados e RECUSADOS (não criar "por precaução"):
--   SERVICO_PRECO(ID_CLINICA) — o catálogo de uma clínica é da ordem de dezenas
--     de linhas; a varredura é mais barata que manter o índice, e o argumento
--     de FK-filha-sem-índice não se aplica porque CLINICA é soft-delete
--     (ST_ATIVA='N'), nunca DELETE físico, então não há operação no pai que
--     dispare a checagem. Se o catálogo crescer de ordem de grandeza, o índice
--     entra numa migration própria, com a medição que o justifique.
--   COBRANCA(ID_SERVICO_PRECO) — o "mix por serviço" da FD-11 agrupa linhas que
--     JÁ foram filtradas por clínica e período (ou seja, pelo índice acima), e
--     a volta para SERVICO_PRECO é por PK, que já é indexada. Índice aqui não
--     entra no plano.
--
-- POR QUE HÁ SPLIT -oracle/-h2 — E O QUE FOI, DE FATO, MEDIDO NESTA TASK
-- Medição própria contra o H2 desta suíte (MODE=Oracle), não herdada:
--   • NUMBER(10,2) é aceito e preserva escala 2 de verdade (o H2 mapeia para
--     NUMERIC(10,2)) — travado em FinanceiroV18MigrationTest.
--   • CREATE INDEX, CHECK, FK, COMMENT, CHAR(1) e TIMESTAMP DEFAULT
--     CURRENT_TIMESTAMP aplicam nos dois bancos com a mesma sintaxe (a variante
--     -h2 é o que a suíte executa; se algo não aplicasse, o Flyway derrubaria o
--     startup do contexto e nenhum teste rodaria).
--   • O H2 ACEITA `DEFAULT SEQ_X.NEXTVAL` (medido na FD-01,
--     UsuarioClinicaV17MigrationTest#h2AceitaNextvalEmExpressaoDeDefault).
-- O QUE **NÃO** FOI MEDIDO, e continua não medido: se o Oracle aceita
-- `DEFAULT NEXT VALUE FOR SEQ_X`. Nenhum teste desta suíte toca Oracle — a
-- conta da FIAP está bloqueada (ORA-28000) e este ciclo não abre conexão com
-- ela.
-- POR QUE O SPLIT FICA MESMO ASSIM: colapsar os dois arquivos em um exige
-- eleger UMA sintaxe de DEFAULT para rodar nos dois bancos, e a única metade
-- verificada é a do H2 aceitando a sintaxe Oracle. Unificar seria uma aposta
-- sobre o banco de PRODUÇÃO validada só pelo banco de teste, com custo
-- assimétrico: o split custa duplicação de arquivo, unificar errado custa o
-- startup do prod. Mesma conclusão da FD-01, pelo mesmo lado NÃO MEDIDO.
--
-- Todo o RESTO do DDL é portável e IDÊNTICO nas duas variantes. As ÚNICAS
-- linhas que divergem são as DUAS do DEFAULT da PK (uma por tabela) — travado
-- por FinanceiroV18MigrationTest#variantesDiferemApenasNasLinhasDoDefaultDaPk,
-- que falha se aparecer uma TERCEIRA divergência, para que o split não vire
-- dívida silenciosa se alguém editar um lado só. A comparação normaliza
-- CRLF/LF de propósito (o repo tem core.autocrlf=true e nenhum .gitattributes):
-- o alvo é divergência SEMÂNTICA, não fim de linha.
-- =============================================================================

CREATE SEQUENCE SEQ_SERVICO_PRECO START WITH 100 INCREMENT BY 1;

CREATE TABLE SERVICO_PRECO (
    ID_SERVICO_PRECO NUMBER(10)    DEFAULT SEQ_SERVICO_PRECO.NEXTVAL PRIMARY KEY,
    ID_CLINICA       NUMBER(10)    NOT NULL,
    NM_SERVICO       VARCHAR2(200) NOT NULL,
    VL_PRECO         NUMBER(10,2)  NOT NULL,
    ST_ATIVA         CHAR(1)       DEFAULT 'S' NOT NULL,
    DT_CRIACAO       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP NOT NULL,
    DT_ATUALIZACAO   TIMESTAMP,
    CONSTRAINT FK_SERVICO_PRECO_CLINICA FOREIGN KEY (ID_CLINICA) REFERENCES CLINICA(ID_CLINICA),
    CONSTRAINT CHK_SERVICO_PRECO_ATIVA  CHECK (ST_ATIVA IN ('S','N')),
    CONSTRAINT CHK_SERVICO_PRECO_VALOR  CHECK (VL_PRECO >= 0)
);

COMMENT ON TABLE  SERVICO_PRECO                IS '.NET owned. Catalogo de precos da clinica (ruling D-2): quanto a clinica cobra por cada servico. NAO e fonte de valor de cobranca ja lancada -- ver COBRANCA.VL_COBRADO.';
COMMENT ON COLUMN SERVICO_PRECO.ID_CLINICA     IS 'Clinica dona do item de catalogo. NOT NULL: tabela de preco e sempre de uma clinica -- e a chave do isolamento multi-tenant do .NET (FD-08).';
COMMENT ON COLUMN SERVICO_PRECO.NM_SERVICO     IS 'Nome do servico como o gestor o cadastra. Sem UNIQUE por clinica de proposito: com soft delete, uma unique impediria recadastrar um servico depois de desativado.';
COMMENT ON COLUMN SERVICO_PRECO.VL_PRECO       IS 'Preco de tabela vigente. Alterar esta coluna NAO altera cobranca ja lancada -- COBRANCA.VL_COBRADO guarda copia do valor no momento do lancamento.';
COMMENT ON COLUMN SERVICO_PRECO.ST_ATIVA       IS 'Soft delete no padrao do projeto (S/N). DELETE fisico nunca acontece.';

CREATE SEQUENCE SEQ_COBRANCA START WITH 100 INCREMENT BY 1;

CREATE TABLE COBRANCA (
    ID_COBRANCA        NUMBER(10)   DEFAULT SEQ_COBRANCA.NEXTVAL PRIMARY KEY,
    ID_EVENTO_CLINICO  NUMBER(10)   NOT NULL,
    ID_CLINICA         NUMBER(10)   NOT NULL,
    ID_SERVICO_PRECO   NUMBER(10),
    VL_COBRADO         NUMBER(10,2) NOT NULL,
    DS_FORMA_PAGAMENTO VARCHAR2(30),
    DT_COBRANCA        TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ST_ATIVA           CHAR(1)      DEFAULT 'S' NOT NULL,
    DT_CRIACAO         TIMESTAMP    DEFAULT CURRENT_TIMESTAMP NOT NULL,
    DT_ATUALIZACAO     TIMESTAMP,
    CONSTRAINT FK_COBRANCA_EVENTO  FOREIGN KEY (ID_EVENTO_CLINICO) REFERENCES EVENTO_CLINICO(ID_EVENTO),
    CONSTRAINT FK_COBRANCA_CLINICA FOREIGN KEY (ID_CLINICA)        REFERENCES CLINICA(ID_CLINICA),
    CONSTRAINT FK_COBRANCA_SERVICO FOREIGN KEY (ID_SERVICO_PRECO)  REFERENCES SERVICO_PRECO(ID_SERVICO_PRECO),
    CONSTRAINT CHK_COBRANCA_ATIVA  CHECK (ST_ATIVA IN ('S','N')),
    CONSTRAINT CHK_COBRANCA_VALOR  CHECK (VL_COBRADO >= 0)
);

COMMENT ON TABLE  COBRANCA                    IS '.NET owned. Lancamento financeiro (ruling D-3), pendurado no atendimento que aconteceu. Sem gateway, transacao externa, status de processamento ou conciliacao (D-1); sem imposto, repasse ou margem (D-6).';
COMMENT ON COLUMN COBRANCA.ID_EVENTO_CLINICO  IS 'Atendimento que originou a cobranca. NOT NULL: nao existe lancamento sem atendimento (D-3). Referencia EVENTO_CLINICO(ID_EVENTO) -- a PK tem nome diferente da coluna, ver cabecalho.';
COMMENT ON COLUMN COBRANCA.ID_CLINICA         IS 'Clinica do lancamento. Denormalizado de EVENTO_CLINICO de proposito: e a coluna que o ApplyTenantFilters do .NET exige (FD-08) e a que os KPI da FD-11 agrupam. Manter coerente com o evento e responsabilidade do service.';
COMMENT ON COLUMN COBRANCA.ID_SERVICO_PRECO   IS 'Item de catalogo que originou o lancamento, quando houve um. NULLABLE: valor avulso sem servico tabelado e lancamento legitimo (D-2). E rastreabilidade de ORIGEM (mix por servico da FD-11), nunca fonte de valor.';
COMMENT ON COLUMN COBRANCA.VL_COBRADO         IS 'Valor efetivamente cobrado, COPIADO no momento do lancamento. Coluna propria de proposito: ler o valor por FK faria mudar preco de tabela reescrever o historico financeiro retroativamente. NAO remover por parecer redundante.';
COMMENT ON COLUMN COBRANCA.DS_FORMA_PAGAMENTO IS 'Descritor do meio usado pelo cliente. Nullable e sem CHECK: exigi-lo forcaria o veterinario a preenche-lo no meio do atendimento, e lista fechada em schema e inventario manual que apodrece. NAO e status de processamento (D-1).';
COMMENT ON COLUMN COBRANCA.DT_COBRANCA        IS 'Data do lancamento. NOT NULL com DEFAULT: linha com data nula seria invisivel a todo KPI por periodo (FD-11) -- receita lancada que nenhum relatorio enxerga.';
COMMENT ON COLUMN COBRANCA.ST_ATIVA           IS 'Soft delete no padrao do projeto (S/N). DELETE fisico nunca acontece.';

CREATE INDEX IDX_COBRANCA_CLINICA_DATA ON COBRANCA(ID_CLINICA, DT_COBRANCA);
CREATE INDEX IDX_COBRANCA_EVENTO       ON COBRANCA(ID_EVENTO_CLINICO);
