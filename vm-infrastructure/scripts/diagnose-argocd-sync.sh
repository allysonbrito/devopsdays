#!/bin/bash
# scripts/diagnose-argocd-sync.sh - DIAGNOSTICAR POR QUE ARGOCD NÃO APLICA RECURSOS

echo "🔍 === DIAGNÓSTICO DETALHADO ARGOCD SYNC ==="
echo "Data: $(date)"
echo

# ============================================
# 1. VERIFICAR STATUS ARGOCD APPLICATIONS
# ============================================
echo "📱 === 1. STATUS DETALHADO DAS APPLICATIONS ==="

for env in dev staging prod; do
    APP_NAME="vm-infrastructure-$env"
    echo "Application: $APP_NAME"
    
    if oc get application $APP_NAME -n argocd &>/dev/null; then
        echo "  ✅ Application existe"
        
        # Status detalhado
        SYNC_STATUS=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
        HEALTH_STATUS=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
        OPERATION_STATE=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.operationState.phase}' 2>/dev/null)
        
        echo "    Sync Status: $SYNC_STATUS"
        echo "    Health Status: $HEALTH_STATUS"
        echo "    Operation State: $OPERATION_STATE"
        
        # Verificar se há mensagens de erro
        ERROR_MSG=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.conditions[?(@.type=="ComparisonError")].message}' 2>/dev/null)
        if [ ! -z "$ERROR_MSG" ]; then
            echo "    ❌ Erro de Comparação: $ERROR_MSG"
        fi
        
        SYNC_ERROR=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.operationState.message}' 2>/dev/null)
        if [ ! -z "$SYNC_ERROR" ]; then
            echo "    ❌ Erro de Sync: $SYNC_ERROR"
        fi
        
        # Verificar recursos gerenciados
        RESOURCES=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.resources[*].kind}' 2>/dev/null)
        if [ ! -z "$RESOURCES" ]; then
            echo "    📦 Recursos detectados: $RESOURCES"
        else
            echo "    ⚠️  Nenhum recurso detectado"
        fi
        
    else
        echo "  ❌ Application não existe"
    fi
    echo
done

# ============================================
# 2. VERIFICAR LOGS ARGOCD CONTROLLER
# ============================================
echo "📝 === 2. LOGS ARGOCD APPLICATION CONTROLLER ==="

echo "Últimos 30 logs do Application Controller:"
oc logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=30 2>/dev/null | grep -E "(error|Error|ERROR|failed|Failed|FAILED)" || echo "  ✅ Nenhum erro encontrado nos logs"

echo
echo "Logs específicos sobre vm-infrastructure:"
oc logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=100 2>/dev/null | grep -i "vm-infrastructure" | tail -10 || echo "  📭 Nenhum log específico encontrado"

# ============================================
# 3. VERIFICAR RBAC DO ARGOCD
# ============================================
echo
echo "🔐 === 3. VERIFICANDO RBAC DO ARGOCD ==="

# Verificar ServiceAccount
ARGOCD_SA=$(oc get sa argocd-application-controller -n argocd -o name 2>/dev/null)
if [ ! -z "$ARGOCD_SA" ]; then
    echo "✅ ServiceAccount: $ARGOCD_SA"
else
    echo "❌ ServiceAccount argocd-application-controller não encontrado"
fi

# Verificar ClusterRoles
echo "ClusterRoles do ArgoCD:"
oc get clusterroles | grep argocd | head -5 || echo "  ❌ Nenhum ClusterRole argocd encontrado"

# Verificar ClusterRoleBindings
echo "ClusterRoleBindings do ArgoCD:"
oc get clusterrolebindings | grep argocd | head -5 || echo "  ❌ Nenhum ClusterRoleBinding argocd encontrado"

# Testar permissões específicas
echo "Testando permissões do ArgoCD:"
ARGOCD_SA_TOKEN=$(oc create token argocd-application-controller -n argocd --duration=60s 2>/dev/null)
if [ ! -z "$ARGOCD_SA_TOKEN" ]; then
    # Testar algumas permissões críticas
    echo "  Testando permissões..."
    
    # VMs
    if oc auth can-i create virtualmachines --as=system:serviceaccount:argocd:argocd-application-controller --all-namespaces 2>/dev/null; then
        echo "    ✅ Pode criar VMs"
    else
        echo "    ❌ NÃO pode criar VMs"
    fi
    
    # Deployments
    if oc auth can-i create deployments --as=system:serviceaccount:argocd:argocd-application-controller --all-namespaces 2>/dev/null; then
        echo "    ✅ Pode criar Deployments"
    else
        echo "    ❌ NÃO pode criar Deployments"
    fi
    
    # Namespaces
    if oc auth can-i create namespaces --as=system:serviceaccount:argocd:argocd-application-controller 2>/dev/null; then
        echo "    ✅ Pode criar Namespaces"
    else
        echo "    ❌ NÃO pode criar Namespaces"
    fi
else
    echo "  ⚠️  Não foi possível obter token para teste de permissões"
fi

# ============================================
# 4. VERIFICAR CONECTIVIDADE GIT
# ============================================
echo
echo "🔗 === 4. VERIFICANDO CONECTIVIDADE GIT ==="

GIT_REPO="https://github.com/allysonbrito/devopsdays.git"

# Verificar se repo está registrado no ArgoCD
if command -v argocd &> /dev/null; then
    echo "Repositórios registrados no ArgoCD:"
    argocd repo list 2>/dev/null | grep -E "(REPO|github)" || echo "  ❌ Nenhum repositório encontrado"
    
    # Verificar conectividade específica
    echo "Testando conectividade com $GIT_REPO:"
    REPO_STATUS=$(argocd repo get $GIT_REPO 2>&1)
    if echo "$REPO_STATUS" | grep -q "CONNECTION_STATUS_SUCCESSFUL"; then
        echo "  ✅ Conectividade OK"
    else
        echo "  ❌ Problema de conectividade:"
        echo "$REPO_STATUS" | head -3
    fi
else
    echo "  ⚠️  ArgoCD CLI não disponível"
fi

# Testar conectividade manual
echo "Testando conectividade HTTP:"
if command -v curl &> /dev/null; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" "$GIT_REPO" --max-time 10)
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "  ✅ Repositório acessível (HTTP $HTTP_STATUS)"
    else
        echo "  ❌ Repositório inacessível (HTTP $HTTP_STATUS)"
    fi
fi

# ============================================
# 5. VERIFICAR SERVIDOR ARGOCD
# ============================================
echo
echo "🖥️  === 5. VERIFICANDO SERVIDOR ARGOCD ==="

# Status dos pods
echo "Status dos pods ArgoCD:"
oc get pods -n argocd | grep -E "(NAME|argocd)" || echo "  ❌ Nenhum pod ArgoCD encontrado"

# Verificar se application controller está rodando
CONTROLLER_POD=$(oc get pods -n argocd -l app.kubernetes.io/name=argocd-application-controller -o name 2>/dev/null | head -1)
if [ ! -z "$CONTROLLER_POD" ]; then
    echo "✅ Application Controller encontrado: $CONTROLLER_POD"
    
    # Verificar CPU/Memory do controller
    echo "Recursos do Application Controller:"
    oc top pod $CONTROLLER_POD -n argocd 2>/dev/null || echo "    ⚠️  Métricas não disponíveis"
    
    # Verificar se pod está ready
    READY_STATUS=$(oc get $CONTROLLER_POD -n argocd -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [ "$READY_STATUS" = "True" ]; then
        echo "    ✅ Pod está Ready"
    else
        echo "    ❌ Pod NÃO está Ready"
    fi
else
    echo "❌ Application Controller não encontrado"
fi

# ============================================
# 6. VERIFICAR NAMESPACES TARGET
# ============================================
echo
echo "🎯 === 6. VERIFICANDO NAMESPACES TARGET ==="

for ns in vm-dev vm-staging vm-prod; do
    echo "Namespace: $ns"
    
    if oc get namespace $ns &>/dev/null; then
        echo "  ✅ Namespace existe"
        
        # Verificar se há resources
        TOTAL_RESOURCES=$(oc get all -n $ns --no-headers 2>/dev/null | wc -l)
        VMS=$(oc get vm -n $ns --no-headers 2>/dev/null | wc -l)
        DVS=$(oc get dv -n $ns --no-headers 2>/dev/null | wc -l)
        
        echo "    📊 Total: $TOTAL_RESOURCES, VMs: $VMS, DataVolumes: $DVS"
        
        if [ $TOTAL_RESOURCES -eq 0 ]; then
            echo "    ⚠️  Namespace vazio - ArgoCD não está criando recursos"
            
            # Verificar eventos do namespace
            echo "    Eventos recentes:"
            oc get events -n $ns --sort-by=.metadata.creationTimestamp | tail -3 2>/dev/null || echo "      📭 Nenhum evento"
        fi
        
        # Verificar se ArgoCD tem acesso ao namespace
        if oc auth can-i create deployments --as=system:serviceaccount:argocd:argocd-application-controller -n $ns 2>/dev/null; then
            echo "    ✅ ArgoCD pode criar recursos neste namespace"
        else
            echo "    ❌ ArgoCD NÃO pode criar recursos neste namespace"
        fi
    else
        echo "  ❌ Namespace não existe"
    fi
    echo
done

# ============================================
# 7. VERIFICAR OPENSHIFT VIRTUALIZATION
# ============================================
echo "🖥️  === 7. VERIFICANDO OPENSHIFT VIRTUALIZATION ==="

if oc get hco -n openshift-cnv &>/dev/null; then
    HCO_STATUS=$(oc get hco -n openshift-cnv -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    if [ "$HCO_STATUS" = "True" ]; then
        echo "✅ OpenShift Virtualization disponível"
    else
        echo "❌ OpenShift Virtualization instalado mas não disponível"
        echo "   Status das condições:"
        oc get hco -n openshift-cnv -o jsonpath='{.items[0].status.conditions[*].type}' 2>/dev/null
    fi
else
    echo "❌ OpenShift Virtualization não instalado"
    echo "   VMs não poderão ser criadas"
fi

# ============================================
# 8. GERAR RELATÓRIO E SUGESTÕES
# ============================================
echo
echo "📋 === 8. RELATÓRIO E SUGESTÕES ==="

echo "🔍 Possíveis causas identificadas:"

# Verificar problemas comuns
ISSUES_FOUND=0

# Applications existem?
TOTAL_APPS=$(oc get applications -n argocd | grep vm-infrastructure | wc -l)
if [ $TOTAL_APPS -eq 0 ]; then
    echo "❌ CRÍTICO: Nenhuma Application ArgoCD encontrada"
    echo "   Solução: oc apply -f applications/vm-infrastructure-applicationset.yaml"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# ArgoCD Controller funcionando?
if [ -z "$CONTROLLER_POD" ]; then
    echo "❌ CRÍTICO: Application Controller não está rodando"
    echo "   Solução: Verificar instalação do ArgoCD"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Permissões?
if ! oc auth can-i create deployments --as=system:serviceaccount:argocd:argocd-application-controller --all-namespaces 2>/dev/null; then
    echo "❌ CRÍTICO: ArgoCD sem permissões para criar recursos"
    echo "   Solução: Verificar ClusterRole e ClusterRoleBinding do ArgoCD"
    ISSUES_FOUND=$((ISSUES_FOUND + 1))
fi

# Namespaces existem?
for ns in vm-dev vm-staging vm-prod; do
    if ! oc get namespace $ns &>/dev/null; then
        echo "⚠️  AVISO: Namespace $ns não existe"
        echo "   Solução: oc new-project $ns"
    fi
done

if [ $ISSUES_FOUND -eq 0 ]; then
    echo "✅ Nenhum problema crítico óbvio detectado"
    echo "🔍 Problemas possíveis mais sutis:"
    echo "  1. Applications em estado de erro - verificar logs detalhados"
    echo "  2. Problemas no kustomize build - testar localmente"
    echo "  3. Sync automático desabilitado - forçar sync manual"
    echo "  4. Network policies bloqueando acesso"
fi

echo
echo "🛠️  Próximos passos recomendados:"
echo "1. ./scripts/fix-argocd-permissions.sh"
echo "2. ./scripts/force-sync-all.sh"
echo "3. Verificar ArgoCD UI para detalhes visuais"
echo "4. Testar kustomize build localmente"

echo
echo "🎯 === DIAGNÓSTICO CONCLUÍDO ==="
