#!/bin/bash
# scripts/fix-gitops-issues.sh - CORRIGIR PROBLEMAS GITOPS

echo "🔧 === CORRIGINDO PROBLEMAS GITOPS ==="

# 1. Verificar e criar namespaces se necessário
echo "1. Verificando namespaces..."
for ns in vm-dev vm-staging vm-prod; do
    if ! oc get namespace $ns &>/dev/null; then
        echo "Criando namespace $ns..."
        oc new-project $ns
        check_status "Namespace $ns criado"
    else
        echo "  ✅ $ns já existe"
    fi
done

# 2. Verificar se ApplicationSet existe
echo "2. Verificando ApplicationSet..."
if ! oc get applicationset vm-infrastructure-set -n argocd &>/dev/null; then
    echo "ApplicationSet não encontrado. Aplicando..."
    if [ -f "applications/vm-infrastructure-applicationset.yaml" ]; then
        oc apply -f applications/vm-infrastructure-applicationset.yaml
        check_status "ApplicationSet aplicado"
    else
        echo "  ❌ Arquivo applications/vm-infrastructure-applicationset.yaml não encontrado"
        echo "  Execute primeiro: ./scripts/setup-complete.sh"
    fi
else
    echo "  ✅ ApplicationSet já existe"
fi

# 3. Forçar sincronização das applications
echo "3. Forçando sincronização..."
if command -v argocd &> /dev/null; then
    for env in dev staging prod; do
        APP_NAME="vm-infrastructure-$env"
        if oc get application $APP_NAME -n argocd &>/dev/null; then
            echo "Sincronizando $APP_NAME..."
            argocd app sync $APP_NAME --force 2>/dev/null && echo "  ✅ $APP_NAME sincronizado" || echo "  ❌ Erro ao sincronizar $APP_NAME"
        fi
    done
else
    echo "  ⚠️  ArgoCD CLI não disponível. Sincronize manualmente via UI"
fi

# 4. Verificar repositório Git no ArgoCD
echo "4. Verificando repositório Git..."
if command -v argocd &> /dev/null; then
    GIT_REPO="https://github.com/allysonbrito/devopsdays.git"
    if ! argocd repo list | grep -q "$GIT_REPO"; then
        echo "Adicionando repositório Git ao ArgoCD..."
        argocd repo add $GIT_REPO
        check_status "Repositório Git adicionado"
    else
        echo "  ✅ Repositório Git já configurado"
    fi
fi

echo "🎯 Correções aplicadas!"
