#!/bin/bash
# scripts/diagnose-gitops.sh - DIAGNÓSTICO COMPLETO GITOPS

echo "🔍 === DIAGNÓSTICO COMPLETO GITOPS ==="
echo "Data: $(date)"
echo "Usuário: $(oc whoami)"
echo "Cluster: $(oc whoami --show-server)"
echo

# Função para verificar status
check_status() {
    if [ $? -eq 0 ]; then
        echo "  ✅ $1"
    else
        echo "  ❌ $1"
        return 1
    fi
}

# ============================================
# 1. VERIFICAR ARGOCD
# ============================================
echo "🔄 === 1. VERIFICANDO ARGOCD ==="

echo "Pods do ArgoCD:"
oc get pods -n argocd 2>/dev/null && check_status "Namespace argocd existe" || echo "  ❌ Namespace argocd não existe"

if oc get pods -n argocd &>/dev/null; then
    ARGOCD_READY=$(oc get pods -n argocd --no-headers | grep -v Running | wc -l)
    if [ $ARGOCD_READY -eq 0 ]; then
        echo "  ✅ Todos os pods ArgoCD estão Running"
    else
        echo "  ❌ $ARGOCD_READY pods ArgoCD não estão Running"
        oc get pods -n argocd | grep -v Running
    fi
fi

echo "ArgoCD Server Route:"
ARGOCD_URL=$(oc get route argocd-server-server -n argocd -o jsonpath='{.spec.host}' 2>/dev/null)
if [ ! -z "$ARGOCD_URL" ]; then
    echo "  ✅ ArgoCD URL: https://$ARGOCD_URL"
else
    echo "  ❌ ArgoCD Route não encontrada"
fi

# ============================================
# 2. VERIFICAR APPLICATIONS ARGOCD
# ============================================
echo
echo "📱 === 2. VERIFICANDO APPLICATIONS ARGOCD ==="

echo "Applications criadas:"
if command -v argocd &> /dev/null; then
    argocd app list 2>/dev/null | grep -E "(NAME|vm-infrastructure)" || echo "  ❌ Nenhuma application vm-infrastructure encontrada"
else
    echo "  ❌ ArgoCD CLI não instalado ou não logado"
    echo "  Verificando via oc..."
    oc get applications -n argocd 2>/dev/null | grep vm-infrastructure || echo "  ❌ Nenhuma application encontrada via oc"
fi

echo "ApplicationSets criados:"
oc get applicationsets -n argocd 2>/dev/null | grep vm-infrastructure || echo "  ❌ Nenhum ApplicationSet encontrado"

# Verificar status específico das applications
echo "Status detalhado das applications:"
for env in dev staging prod; do
    APP_NAME="vm-infrastructure-$env"
    if oc get application $APP_NAME -n argocd &>/dev/null; then
        echo "  $APP_NAME:"
        SYNC_STATUS=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.sync.status}' 2>/dev/null)
        HEALTH_STATUS=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.health.status}' 2>/dev/null)
        echo "    Sync: $SYNC_STATUS"
        echo "    Health: $HEALTH_STATUS"
        
        if [ "$SYNC_STATUS" != "Synced" ] || [ "$HEALTH_STATUS" != "Healthy" ]; then
            echo "    ⚠️  Application com problemas!"
        fi
    else
        echo "  ❌ $APP_NAME não encontrado"
    fi
done

# ============================================
# 3. VERIFICAR NAMESPACES TARGET
# ============================================
echo
echo "🏗️  === 3. VERIFICANDO NAMESPACES TARGET ==="

for ns in vm-dev vm-staging vm-prod; do
    if oc get namespace $ns &>/dev/null; then
        echo "  ✅ $ns existe"
        
        # Verificar recursos no namespace
        PODS=$(oc get pods -n $ns --no-headers 2>/dev/null | wc -l)
        VMS=$(oc get vm -n $ns --no-headers 2>/dev/null | wc -l)
        DEPLOYMENTS=$(oc get deployments -n $ns --no-headers 2>/dev/null | wc -l)
        
        echo "    📊 Recursos: $PODS pods, $VMS VMs, $DEPLOYMENTS deployments"
        
        if [ $PODS -eq 0 ] && [ $VMS -eq 0 ] && [ $DEPLOYMENTS -eq 0 ]; then
            echo "    ⚠️  Namespace vazio - recursos não foram criados!"
        fi
    else
        echo "  ❌ $ns não existe"
    fi
done

# ============================================
# 4. VERIFICAR LOGS ARGOCD
# ============================================
echo
echo "📝 === 4. VERIFICANDO LOGS ARGOCD ==="

echo "Logs do ArgoCD Application Controller (últimas 20 linhas):"
oc logs -n argocd -l app.kubernetes.io/name=argocd-application-controller --tail=20 2>/dev/null | grep -i error || echo "  ✅ Nenhum erro nos logs do controller"

echo "Logs do ArgoCD Server (últimas 10 linhas com erro):"
oc logs -n argocd -l app.kubernetes.io/name=argocd-server --tail=50 2>/dev/null | grep -i error | tail -10 || echo "  ✅ Nenhum erro nos logs do server"

# ============================================
# 5. VERIFICAR EVENTOS OPENSHIFT
# ============================================
echo
echo "⚡ === 5. VERIFICANDO EVENTOS OPENSHIFT ==="

for ns in vm-dev vm-staging vm-prod argocd; do
    if oc get namespace $ns &>/dev/null; then
        echo "Eventos recentes em $ns:"
        RECENT_EVENTS=$(oc get events -n $ns --sort-by=.metadata.creationTimestamp 2>/dev/null | tail -5)
        if [ ! -z "$RECENT_EVENTS" ]; then
            echo "$RECENT_EVENTS"
        else
            echo "  📭 Nenhum evento recente"
        fi
        echo
    fi
done

# ============================================
# 6. VERIFICAR PERMISSÕES ARGOCD
# ============================================
echo
echo "🔐 === 6. VERIFICANDO PERMISSÕES ARGOCD ==="

# Verificar ServiceAccount do ArgoCD
ARGOCD_SA=$(oc get sa -n argocd | grep argocd-application-controller || echo "ServiceAccount não encontrado")
echo "ServiceAccount ArgoCD: $ARGOCD_SA"

# Verificar ClusterRole/ClusterRoleBinding
echo "ClusterRoles do ArgoCD:"
oc get clusterroles | grep argocd || echo "  ❌ Nenhum ClusterRole argocd encontrado"

echo "ClusterRoleBindings do ArgoCD:"
oc get clusterrolebindings | grep argocd || echo "  ❌ Nenhum ClusterRoleBinding argocd encontrado"

# ============================================
# 7. VERIFICAR CONECTIVIDADE GIT
# ============================================
echo
echo "🔗 === 7. VERIFICANDO CONECTIVIDADE GIT ==="

GIT_REPO="https://github.com/allysonbrito/devopsdays.git"
echo "Testando conectividade com $GIT_REPO..."

if command -v curl &> /dev/null; then
    HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" $GIT_REPO --max-time 10)
    if [ "$HTTP_STATUS" = "200" ]; then
        echo "  ✅ Repositório Git acessível (HTTP $HTTP_STATUS)"
    else
        echo "  ❌ Repositório Git inacessível (HTTP $HTTP_STATUS)"
    fi
else
    echo "  ⚠️  curl não disponível para testar conectividade"
fi

# Verificar se ArgoCD tem acesso ao repo
if command -v argocd &> /dev/null; then
    echo "Repositórios registrados no ArgoCD:"
    argocd repo list 2>/dev/null | grep -E "(REPO|github)" || echo "  ❌ Nenhum repositório GitHub registrado"
fi

# ============================================
# 8. VERIFICAR RECURSOS ESPECÍFICOS
# ============================================
echo
echo "🎯 === 8. VERIFICANDO RECURSOS ESPECÍFICOS ==="

# Verificar OpenShift Virtualization
echo "OpenShift Virtualization:"
if oc get hco -n openshift-cnv &>/dev/null; then
    HCO_STATUS=$(oc get hco -n openshift-cnv -o jsonpath='{.items[0].status.conditions[?(@.type=="Available")].status}' 2>/dev/null)
    if [ "$HCO_STATUS" = "True" ]; then
        echo "  ✅ OpenShift Virtualization disponível"
    else
        echo "  ❌ OpenShift Virtualization não disponível"
    fi
else
    echo "  ❌ OpenShift Virtualization não instalado"
fi

# Verificar Storage Classes
echo "Storage Classes:"
DEFAULT_SC=$(oc get sc -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' 2>/dev/null)
if [ ! -z "$DEFAULT_SC" ]; then
    echo "  ✅ Storage Class padrão: $DEFAULT_SC"
else
    echo "  ❌ Nenhuma Storage Class padrão configurada"
    oc get sc 2>/dev/null | head -5
fi

# ============================================
# 9. GERAR RELATÓRIO RESUMO
# ============================================
echo
echo "📋 === 9. RESUMO DO DIAGNÓSTICO ==="

# Verificar problemas críticos
CRITICAL_ISSUES=0

# ArgoCD rodando?
if ! oc get pods -n argocd &>/dev/null; then
    echo "🚨 CRÍTICO: ArgoCD não está instalado ou namespace não existe"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Applications criadas?
if ! oc get applications -n argocd 2>/dev/null | grep -q vm-infrastructure; then
    echo "🚨 CRÍTICO: Nenhuma Application ArgoCD criada"
    CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
fi

# Namespaces target existem?
for ns in vm-dev; do
    if ! oc get namespace $ns &>/dev/null; then
        echo "🚨 CRÍTICO: Namespace $ns não existe"
        CRITICAL_ISSUES=$((CRITICAL_ISSUES + 1))
    fi
done

# OpenShift Virtualization?
if ! oc get hco -n openshift-cnv &>/dev/null; then
    echo "⚠️  AVISO: OpenShift Virtualization pode não estar instalado"
fi

echo
if [ $CRITICAL_ISSUES -eq 0 ]; then
    echo "✅ Nenhum problema crítico detectado"
    echo "🔍 Se os recursos ainda não estão sendo criados, verifique:"
    echo "   1. Logs detalhados das applications"
    echo "   2. Sincronização manual via ArgoCD UI"
    echo "   3. Permissões específicas dos recursos"
else
    echo "❌ $CRITICAL_ISSUES problema(s) crítico(s) detectado(s)"
    echo "🔧 Corrija os problemas críticos antes de prosseguir"
fi

echo
echo "🎯 === DIAGNÓSTICO CONCLUÍDO ==="
echo "Para próximos passos, execute:"
echo "  ./scripts/fix-gitops-issues.sh"
