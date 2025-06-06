#!/bin/bash
# scripts/test-simple.sh - TESTE PASSO A PASSO

echo "🧪 === TESTE PASSO A PASSO ==="

echo "1. Testando base..."
if kustomize build base/ > /dev/null 2>&1; then
    echo "  ✅ Base OK"
else
    echo "  ❌ Base FAILED"
    echo "  Erro:"
    kustomize build base/ 2>&1 | head -3
fi

echo "2. Testando DEV..."
if kustomize build environments/dev/ > /dev/null 2>&1; then
    echo "  ✅ DEV OK"
else
    echo "  ❌ DEV FAILED" 
    echo "  Erro:"
    kustomize build environments/dev/ 2>&1 | head -3
fi

echo "3. Listando recursos gerados no DEV..."
if kustomize build environments/dev/ > /tmp/dev.yaml 2>/dev/null; then
    echo "  Recursos:"
    grep "^kind:" /tmp/dev.yaml | sort | uniq -c
fi
