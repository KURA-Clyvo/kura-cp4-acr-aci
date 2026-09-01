# Prompt de continuidade — CP4 ACR/ACI, Sessão 2

Cole este prompt inteiro pra abrir a sessão 2. Ele é autocontido — não depende de você lembrar
nada da sessão 1.

---

Estou continuando a entrega do CP4 de DevOps Tools & Cloud Computing (FIAP) — "Imagem e
Containers em Nuvem (ACR/ACI)", Grupo 3. **Leia primeiro, nesta ordem**:

1. `C:\Users\labsfiap\kura-cp4-acr-aci\STATUS-SESSAO-1.md` — o que foi feito, os 5 problemas
   reais encontrados e corrigidos, e exatamente onde a sessão 1 parou.
2. `C:\Users\labsfiap\kura-cp4-acr-aci\README.md` — arquitetura e How-To completo.
3. `C:\Users\labsfiap\kura-cp4-acr-aci\NOTAS-PARA-O-MAESTRO.md` — decisões técnicas do
   scaffolding original.

**Não repita as investigações já feitas** — a seção 5 do `STATUS-SESSAO-1.md` lista
explicitamente o que não precisa ser refeito.

## Contexto essencial (resumo, o STATUS tem o detalhe)

- Repo: `https://github.com/KURA-Clyvo/kura-cp4-acr-aci`, público, até o commit `a273da3`.
- Time: Grupo 3, RM prefixo `RM562999` (Felipe Ferrete, representante).
- Azure: subscription "2026 - 2TDSPF - Felipe Ferrete Soares Lemes - RM562999", resource group
  `rm562999-kura-cp4-rg`, região `centralus`. `az login`/`gh auth login` já estavam feitos na
  sessão 1 nesta máquina — confirme se ainda estão (`az account show`, `gh auth status`); se for
  outra máquina, refaça.
- **Repos-fonte esperados como diretórios irmãos**: `C:\Users\labsfiap\backend-clinica-dotnet`,
  `C:\Users\labsfiap\backend-tutor-java` (confirme com `ls` — pode ter mudado de máquina).

## Passo 0 — confirmar o que existe

```bash
az account show -o table
az resource list --resource-group rm562999-kura-cp4-rg -o table
cd /c/Users/labsfiap/kura-cp4-acr-aci && git log --oneline -5 && git status --short
ls .env 2>&1   # se nao existir, cp .env.example .env e preencher (openssl rand -base64 ...)
```

Se o resource group não existir mais (foi limpo por custo, ou é outra sessão/máquina), pule pro
"Passo 1" normalmente — `azure/deploy.sh` recria tudo do zero, é idempotente.

## Passo 1 — retomar exatamente de onde parou: confirmar (ou terminar de corrigir) o Oracle

O ACI `rm562999-kura-oracle-db` foi recriado ao vivo com o fix de cgroup v1 (commit `a273da3`,
imagem já publicada no ACR como `:latest`) e mostrou progresso real (nunca tinha passado do
`restartCount: 0` tão longe no boot antes), mas `restartCount` foi a 1 antes da sessão acabar, e
o log daquele crash específico não foi capturado.

**Primeira coisa a fazer, antes de qualquer mudança de código:**

```bash
# Loop curto pra pegar o log do restart atual/próximo antes dele ser limpo
for i in $(seq 1 10); do
  echo "=== tentativa $i ==="
  az container logs --name rm562999-kura-oracle-db --resource-group rm562999-kura-cp4-rg 2>&1 | tail -40
  az container show --name rm562999-kura-oracle-db --resource-group rm562999-kura-cp4-rg \
    --query "containers[0].instanceView.{state:currentState.state, restartCount:restartCount}" -o json
  sleep 15
done
```

Três cenários possíveis, e o que fazer em cada um:

- **Se o log mostrar `DATABASE IS READY TO USE!` e `restartCount` parar de subir, com a porta
  1521 respondendo** (`timeout 5 bash -c "cat < /dev/tcp/rm562999-kura-oracle-db.centralus.azurecontainer.io/1521"`):
  o fix funcionou de verdade. Vá direto pro **Passo 2**.
- **Se o log mostrar `ORA-01081` de novo** (o mesmo erro de antes, só que mais tarde no boot): o
  shim de cgroup ajudou mas não resolveu tudo — pode haver uma SEGUNDA leitura de arquivo cgroup
  em outro ponto do entrypoint que o shim não cobriu. Repita o teste `find`/`grep` que a sessão 1
  não chegou a fazer: `docker run --rm --user root --entrypoint sh kura-oracle-db:local -c "grep -rn 'cgroup' /opt/oracle/*.sh /opt/oracle/scripts/*.sh 2>/dev/null"`
  pra achar TODOS os pontos do script que leem cgroup, não só o primeiro.
- **Se o log mostrar um erro DIFERENTE de `ORA-01081`**: é um problema novo, documente-o em
  `STATUS-SESSAO-1.md` (ou crie `STATUS-SESSAO-2.md`) com a mesma disciplina de evidência da
  sessão 1 — nunca assumir causa sem confirmar no log real.

## Passo 2 — depois do Oracle saudável, seguir o `README.md` §4 dali em diante

1. Rodar o passo de backup real pro Storage Account (já está em `azure/deploy.sh`, procure por
   `az container exec` — é o passo que copia `/opt/oracle/oradata` pro volume Azure Files
   `/mnt/kura-backup`). Confirmar que gerou arquivo de verdade:
   ```bash
   az storage file list --account-name rm562999kurastorage \
     --account-key "$(az storage account keys list --account-name rm562999kurastorage --resource-group rm562999-kura-cp4-rg --query '[0].value' -o tsv)" \
     --share-name kura-oracle-data --path "oradata-snapshot" -o table
   ```
2. Rodar `./azure/deploy.sh` de novo (ele é idempotente — vai pular RG/ACR/storage/imagens que já
   existem e ir direto pro que falta: ACI do `.NET`, e o ACI do Java bônus se
   `DEPLOY_JAVA_BONUS=true` no `.env`). **Importante**: o `.NET` só funciona depois que o Java
   aplicar o Flyway — confirme `DEPLOY_JAVA_BONUS=true` antes de rodar.
3. `./azure/verify.sh` — precisa passar 100% (núcleo Oracle + `.NET`).
4. `BASE_URL=http://<fqdn-do-aci-dotnet>:8080 ./tests/smoke-cp4.sh` — roda o CRUD completo e
   imprime o `sqlplus` pronto pra tirar o `SELECT` de prova.
5. Gravar o vídeo — roteiro pronto em `docs/ROTEIRO-VIDEO.md`.
6. Exportar `docs/CAPA-ENTREGA.html` pra PDF (abrir no navegador, Ctrl+P → salvar como PDF →
   renomear `Grupo3_container.pdf`) e enviar pro Felipe subir no Teams.
7. **`./azure/teardown.sh` no final** — obrigatório, não deixar recurso ligado.

## Regras que valem pra esta sessão também

- **Nunca encerrar o turno com working tree suja** — commitar cada fix assim que funcionar,
  antes de partir pro próximo passo.
- **Documentar achado real com evidência, nunca suposição** — foi assim que os 5 problemas da
  sessão 1 foram resolvidos de verdade em vez de ficar tentando "seria isso, será aquilo".
  Quando um fix não funcionar, capturar o log/erro exato antes de tentar o próximo, e escrever
  isso em algum `STATUS-SESSAO-N.md`.
- Se a sessão 2 também não terminar a tempo, **repita este padrão**: escreva
  `STATUS-SESSAO-2.md` e `PROMPT_CONTINUIDADE_SESSAO_3.md` antes de encerrar — não deixe o
  handoff pra memória de ninguém.
