#!/bin/bash
# scripts/debug-kustomize.sh - DIAGNOSTICAR PROBLEMA

echo "🔍 === DEBUGANDO PROBLEMA KUSTOMIZE ==="

# Verificar se estamos no diretório correto
if [[ $(basename $(pwd)) != "vm-infrastructure" ]]; then
    echo "❌ Execute dentro do diretório vm-infrastructure"
    exit 1
fi

echo "📁 Verificando estrutura de arquivos..."

# Verificar arquivos base
echo "Arquivos base:"
find base/ -name "*.yaml" -exec echo "  ✅ {}" \; 2>/dev/null || echo "  ❌ Diretório base/ não encontrado"

echo
echo "📋 Verificando conteúdo dos arquivos base..."

# Verificar se vm-template.yaml existe e tem conteúdo
if [[ -f "base/vm/vm-template.yaml" ]]; then
    echo "✅ base/vm/vm-template.yaml existe"
    echo "Recursos encontrados:"
    grep "^kind:" base/vm/vm-template.yaml | while read line; do
        echo "  - $line"
    done
    echo "Nomes encontrados:"
    grep "^  name:" base/vm/vm-template.yaml | while read line; do
        echo "  - $line"
    done
else
    echo "❌ base/vm/vm-template.yaml NÃO EXISTE"
fi

echo
echo "🔧 Testando build do base isoladamente..."

# Testar build apenas do base
if kustomize build base/ > /tmp/base-test.yaml 2>&1; then
    echo "✅ Base build OK"
    echo "Recursos no base:"
    grep "^kind:" /tmp/base-test.yaml | sort | uniq -c
    echo "VMs encontradas:"
    grep -A2 "kind: VirtualMachine" /tmp/base-test.yaml | grep "name:"
else
    echo "❌ Base build FAILED"
    echo "Erro:"
    kustomize build base/ 2>&1
fi

echo
echo "📝 Verificando patches DEV..."
if [[ -f "environments/dev/vm-config.yaml" ]]; then
    echo "✅ dev/vm-config.yaml existe"
    echo "Patches tentando aplicar em:"
    grep -A2 "kind: VirtualMachine" environments/dev/vm-config.yaml | grep "name:" || echo "  ❌ Nenhum nome encontrado"
else
    echo "❌ dev/vm-config.yaml NÃO EXISTE"
fi

echo
echo "🎯 === DIAGNÓSTICO CONCLUÍDO ==="
