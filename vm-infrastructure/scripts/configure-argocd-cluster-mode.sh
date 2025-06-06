#!/bin/bash
# scripts/configure-argocd-cluster-mode.sh - CONFIGURAR MODO CLUSTER

echo "🔧 === CONFIGURANDO ARGOCD PARA MODO CLUSTER ==="

# Verificar permissões
if ! oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
    echo "❌ Permissões insuficientes para configurar modo cluster"
    echo "Use a Opção 1 (modo namespaced)"
    exit 1
fi

# Verificar se ArgoCD está instalado via Operator
if oc get argocd argocd-server -n argocd &>/dev/null; then
    echo "📝 Atualizando ArgoCD CR para modo cluster..."
    
    # Patch para habilitar modo cluster
    oc patch argocd argocd-server -n argocd --type='merge' -p='{"spec":{"server":{"extraArgs":["--insecure"]}, "controller":{"env":[{"name":"ARGOCD_APPLICATION_NAMESPACES","value":"argocd"}]}}}'
    
    echo "✅ ArgoCD configurado para modo cluster"
    echo "⏳ Aguardando pods reiniciarem..."
    
    # Aguardar pods reiniciarem
    oc rollout restart deployment argocd-server-server -n argocd
    oc rollout restart deployment argocd-server-application-controller -n argocd
    
    # Aguardar estar pronto
    oc rollout status deployment argocd-server-server -n argocd
    oc rollout status deployment argocd-server-application-controller -n argocd
    
    echo "✅ ArgoCD reiniciado em modo cluster"
else
    echo "❌ ArgoCD não instalado via Operator - não é possível configurar modo cluster"
    echo "Use a Opção 1 (modo namespaced)"
fi
