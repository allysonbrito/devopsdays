#!/bin/bash
# scripts/fix-argocd-permissions.sh - CORRIGIR PERMISSÕES ARGOCD

echo "🔧 === CORRIGINDO PERMISSÕES ARGOCD ==="

# Verificar se ArgoCD está instalado via Operator
if oc get argocd argocd-server -n argocd &>/dev/null; then
    echo "✅ ArgoCD instalado via Operator"
    
    # Verificar se tem permissões cluster-admin
    if oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
        echo "📝 Aplicando permissões cluster-admin para ArgoCD..."
        
        cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: argocd-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: argocd-application-controller
  namespace: argocd
- kind: ServiceAccount
  name: argocd-server
  namespace: argocd
EOF
        
        echo "✅ Permissões cluster-admin aplicadas"
        
        # Reiniciar ArgoCD controller
        echo "🔄 Reiniciando ArgoCD Application Controller..."
        oc rollout restart deployment argocd-application-controller -n argocd
        oc rollout status deployment argocd-application-controller -n argocd
        
        echo "✅ ArgoCD Application Controller reiniciado"
    else
        echo "❌ Você não tem permissões cluster-admin para corrigir isso"
        echo "   Contate o administrador do cluster"
    fi
else
    echo "❌ ArgoCD não instalado via Operator"
    echo "   Instale o ArgoCD Operator primeiro"
fi
