#!/bin/sh
# =============================================================================
# KURA CP4 - shim de compatibilidade cgroup v1 -> v2 para o entrypoint da
# imagem gvenzl/oracle-xe.
#
# ACHADO REAL (2026-09-01): rodando esta imagem sem alteracao no Azure
# Container Instances, o container entra em crash loop consistente
# (restartCount incrementando sem parar, ExitCode 204) logo apos o listener
# subir, com "ORA-01081: cannot start already-running ORACLE" no log --
# mesmo com oradata em disco LOCAL (nao em volume de rede) e recursos
# generosos (ate 4 vCPU / 8GB testados). A MESMA imagem funciona perfeitamente
# no Docker Desktop local (confirmado, "DATABASE IS READY TO USE!" sem erro).
#
# Isolado por teste direto (nao suposicao): o ACI expoe cgroup v1
# (/sys/fs/cgroup/memory/memory.limit_in_bytes existe,
# /sys/fs/cgroup/memory.max NAO existe), enquanto o Docker Desktop local usa
# cgroup v2 unificado (/sys/fs/cgroup/memory.max = "max"). O
# container-entrypoint.sh da imagem gvenzl le o caminho v2 -- bate com a
# issue publica gvenzl/oci-oracle-xe#191 sobre "/sys/fs/cgroup/memory.max: No
# such file or directory" na linha 293 do script.
#
# Este shim roda ANTES do entrypoint real, ainda como root (a imagem base
# muda para o usuario 'oracle' via USER, entao aqui a gente assume esse
# controle de volta no nosso proprio Dockerfile): cria os arquivos
# equivalentes de cgroup v2 a partir dos valores reais de cgroup v1, depois
# derruba privilegio pro usuario 'oracle' e entrega o processo pro entrypoint
# de verdade. So escreve se o caminho v2 nao existir -- em host com cgroup v2
# de verdade (Docker Desktop, a maioria dos ambientes modernos) isto e um
# no-op completo.
# =============================================================================
set -e

if [ ! -e /sys/fs/cgroup/memory.max ] && [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
    LIMITE=$(cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo "")
    if [ -n "$LIMITE" ]; then
        # cgroup v1 usa um numero enorme (proximo do limite de int64) para
        # sinalizar "sem limite"; cgroup v2 usa o literal "max" para o mesmo caso.
        if [ "$LIMITE" -gt 4611686018427387904 ] 2>/dev/null; then
            echo "max" > /sys/fs/cgroup/memory.max 2>/dev/null || true
        else
            echo "$LIMITE" > /sys/fs/cgroup/memory.max 2>/dev/null || true
        fi
    fi
fi

if [ ! -e /sys/fs/cgroup/cpu.max ] && [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
    QUOTA=$(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us 2>/dev/null || echo "-1")
    PERIODO=$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us 2>/dev/null || echo "100000")
    if [ "$QUOTA" = "-1" ]; then
        echo "max $PERIODO" > /sys/fs/cgroup/cpu.max 2>/dev/null || true
    else
        echo "$QUOTA $PERIODO" > /sys/fs/cgroup/cpu.max 2>/dev/null || true
    fi
fi

# 'su'/'gosu' nao existem nesta imagem (slim) -- usa 'chroot --userspec' pra
# raiz '/' (chroot no-op, so serve pelo efeito colateral de trocar uid/gid
# antes do exec) em vez de um binario dedicado de troca de usuario. UID/GID
# numericos porque o grupo primario do usuario 'oracle' (uid 54321) se chama
# 'oinstall' (gid 54321), nao 'oracle' -- '--userspec=oracle:oracle' falha
# com "invalid group" por causa disso (confirmado rodando local).
#
# 'chroot' reseta o cwd pra '/' do novo root mesmo quando o novo root E o
# mesmo '/' de sempre -- container-entrypoint.sh usa caminho relativo
# (./createAppUser) e precisa rodar com cwd = WORKDIR da imagem base
# (/opt/oracle, confirmado com `docker inspect`), por isso o `cd` explicito
# dentro do `sh -c` abaixo (confirmado local: sem isso da
# "./createAppUser: No such file or directory").
exec chroot --userspec=54321:54321 --groups=54321,54322,54323,54324,54325,54326,54330 / \
    sh -c 'cd /opt/oracle && exec container-entrypoint.sh'
