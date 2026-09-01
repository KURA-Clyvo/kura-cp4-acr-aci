# DDL das tabelas — CP4

Estes 19 arquivos são as migrations Flyway **reais e atuais** do ecossistema KURA
(`backend-tutor-java/src/main/resources/db/migration/` + `db/migration-oracle/`,
`V1__initial_schema.sql` → `V19__usuario_clinica_fk_composta.sql`), copiadas sem alteração.

**Por que isto e não um dump `CREATE TABLE` avulso**: Flyway é a única autoridade de DDL
do ecossistema (ver `CLAUDE.md` do workspace de planejamento) — não existe um script de
schema "oficial" separado das migrations. Estes arquivos SÃO o que cria as ~27 tabelas
(`CLINICA`, `VETERINARIO`, `TUTOR`, `PET`, `AGENDAMENTO`, `USUARIO_CLINICA`, etc.), suas
PKs, FKs, sequences e constraints — exatamente o que a rubrica pede ("tabelas, colunas,
PK etc").

**Como elas chegam ao banco no CP4**: automaticamente. O container do backend Java
(`backend-tutor-java`), ao subir em profile `prod` contra o Oracle vazio do ACI, aplica
V1→V19 sozinho na primeira inicialização — não é preciso rodar nenhum destes arquivos à
mão. Ver `../../azure/deploy.sh` (`DEPLOY_JAVA_BONUS=true`) e `../../NOTAS-PARA-O-MAESTRO.md`.

Ordem de aplicação = ordem numérica do prefixo `V<n>__`. As duas pastas de origem foram
mescladas aqui porque, para o Oracle real (o único motor usado neste CP4 — nunca H2),
o Flyway aplica os arquivos de `db/migration/` (SQL portável) e `db/migration-oracle/`
(PL/SQL específico Oracle) juntos, pela mesma numeração.
