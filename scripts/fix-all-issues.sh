#!/bin/bash
# scripts/fix-all-issues.sh - CORREÇÃO COMPLETA

set -e

echo "🔧 === CORREÇÃO COMPLETA DOS PROBLEMAS ==="

# Função para verificar status
check_status() {
    if [ $? -eq 0 ]; then
        echo "  ✅ $1"
        return 0
    else
        echo "  ❌ $1"
        return 1
    fi
}

# Verificar diretório
if [[ $(basename $(pwd)) != "vm-infrastructure" ]]; then
    echo "❌ Execute dentro do diretório vm-infrastructure"
    echo "Diretório atual: $(pwd)"
    exit 1
fi

echo "📁 Diretório: $(pwd)"

# ============================================
# 1. CONFIGURAR ARGOCD CLI
# ============================================
echo
echo "🔗 === 1. CONFIGURANDO ARGOCD CLI ==="

# Obter URL e senha do ArgoCD
ARGOCD_URL=$(oc get route argocd-server-server -n argocd -o jsonpath='{.spec.host}' 2>/dev/null)
if [ -z "$ARGOCD_URL" ]; then
    echo "❌ ArgoCD route não encontrada. Verifique se ArgoCD está instalado."
    echo "Para instalar ArgoCD, execute: oc apply -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml"
    exit 1
fi

ARGOCD_PASSWORD=$(oc get secret argocd-server-cluster -n argocd -o jsonpath='{.data.admin\.password}' 2>/dev/null | base64 -d)
if [ -z "$ARGOCD_PASSWORD" ]; then
    echo "❌ Senha do ArgoCD não encontrada"
    exit 1
fi

echo "ArgoCD URL: https://$ARGOCD_URL"
echo "Fazendo login no ArgoCD..."

# Login no ArgoCD CLI
if command -v argocd &> /dev/null; then
    argocd login $ARGOCD_URL --username admin --password $ARGOCD_PASSWORD --insecure --grpc-web
    check_status "Login ArgoCD realizado"
else
    echo "❌ ArgoCD CLI não instalado"
    echo "Instale com: curl -sSL -o argocd-linux-amd64 https://github.com/argoproj/argo-cd/releases/latest/download/argocd-linux-amd64 && sudo install -m 555 argocd-linux-amd64 /usr/local/bin/argocd"
    exit 1
fi

# ============================================
# 2. CRIAR ESTRUTURA COMPLETA SE NÃO EXISTIR
# ============================================
echo
echo "📁 === 2. CRIANDO ESTRUTURA COMPLETA ==="

# Executar setup completo se arquivos não existem
if [ ! -f "applications/vm-infrastructure-applicationset.yaml" ]; then
    echo "Arquivos não encontrados. Executando setup completo..."
    
    if [ -f "scripts/setup-complete.sh" ]; then
        chmod +x scripts/setup-complete.sh
        ./scripts/setup-complete.sh
        check_status "Setup completo executado"
    else
        echo "Script setup-complete.sh não encontrado. Criando arquivos manualmente..."
        
        # Criar diretórios
        mkdir -p {applications,environments/{dev,staging,prod},base/{vm,containers}}
        
        # Criar ApplicationSet manualmente
        cat > applications/vm-infrastructure-applicationset.yaml << 'EOF'
apiVersion: argoproj.io/v1alpha1
kind: ApplicationSet
metadata:
  name: vm-infrastructure-set
  namespace: argocd
spec:
  generators:
  - list:
      elements:
      - env: dev
        namespace: vm-dev
      - env: staging
        namespace: vm-staging
      - env: prod
        namespace: vm-prod
  template:
    metadata:
      name: 'vm-infrastructure-{{env}}'
    spec:
      project: default
      source:
        repoURL: https://github.com/allysonbrito/devopsdays.git
        targetRevision: main
        path: 'vm-infrastructure/environments/{{env}}'
      destination:
        server: https://kubernetes.default.svc
        namespace: '{{namespace}}'
      syncPolicy:
        automated:
          prune: true
          selfHeal: true
        syncOptions:
        - CreateNamespace=true
EOF
        
        echo "✅ ApplicationSet criado manualmente"
    fi
fi

# ============================================
# 3. CRIAR NAMESPACES
# ============================================
echo
echo "🏗️  === 3. CRIANDO NAMESPACES ==="

for ns in vm-dev vm-staging vm-prod; do
    if ! oc get namespace $ns &>/dev/null; then
        echo "Criando namespace $ns..."
        oc new-project $ns
        check_status "Namespace $ns criado"
    else
        echo "  ✅ $ns já existe"
    fi
done

# ============================================
# 4. APLICAR APPLICATIONSET
# ============================================
echo
echo "📱 === 4. APLICANDO APPLICATIONSET ==="

if [ -f "applications/vm-infrastructure-applicationset.yaml" ]; then
    echo "Aplicando ApplicationSet..."
    oc apply -f applications/vm-infrastructure-applicationset.yaml
    check_status "ApplicationSet aplicado"
    
    # Aguardar criação das applications
    echo "Aguardando criação das applications (30 segundos)..."
    sleep 30
    
    # Verificar se applications foram criadas
    APPS_CREATED=$(oc get applications -n argocd | grep vm-infrastructure | wc -l)
    echo "Applications criadas: $APPS_CREATED"
    
else
    echo "❌ Arquivo ApplicationSet ainda não existe"
    exit 1
fi

# ============================================
# 5. ADICIONAR REPOSITÓRIO GIT
# ============================================
echo
echo "🔗 === 5. CONFIGURANDO REPOSITÓRIO GIT ==="

GIT_REPO="https://github.com/allysonbrito/devopsdays.git"
echo "Adicionando repositório: $GIT_REPO"

# Verificar se repo já está configurado
if argocd repo list | grep -q "$GIT_REPO"; then
    echo "  ✅ Repositório já configurado"
else
    argocd repo add $GIT_REPO
    check_status "Repositório Git adicionado"
fi

# ============================================
# 6. SINCRONIZAR APPLICATIONS
# ============================================
echo
echo "🔄 === 6. SINCRONIZANDO APPLICATIONS ==="

# Aguardar um pouco mais para applications serem criadas
sleep 10

for env in dev staging prod; do
    APP_NAME="vm-infrastructure-$env"
    echo "Sincronizando $APP_NAME..."
    
    if oc get application $APP_NAME -n argocd &>/dev/null; then
        # Forçar refresh primeiro
        argocd app get $APP_NAME --refresh
        
        # Depois sincronizar
        argocd app sync $APP_NAME --force
        
        if [ $? -eq 0 ]; then
            echo "  ✅ $APP_NAME sincronizado"
        else
            echo "  ⚠️  $APP_NAME com problemas - verificando logs..."
            argocd app logs $APP_NAME --tail 5
        fi
    else
        echo "  ❌ Application $APP_NAME não encontrada"
    fi
done

# ============================================
# 7. VERIFICAR RESULTADOS
# ============================================
echo
echo "📊 === 7. VERIFICANDO RESULTADOS ==="

# Aguardar recursos serem criados
echo "Aguardando recursos serem criados (60 segundos)..."
sleep 60

for ns in vm-dev vm-staging vm-prod; do
    if oc get namespace $ns &>/dev/null; then
        echo "Namespace: $ns"
        
        PODS=$(oc get pods -n $ns --no-headers 2>/dev/null | wc -l)
        VMS=$(oc get vm -n $ns --no-headers 2>/dev/null | wc -l)
        DEPLOYMENTS=$(oc get deployments -n $ns --no-headers 2>/dev/null | wc -l)
        DATAVOLUMES=$(oc get dv -n $ns --no-headers 2>/dev/null | wc -l)
        
        echo "  📊 Recursos: $PODS pods, $VMS VMs, $DEPLOYMENTS deployments, $DATAVOLUMES DVs"
        
        if [ $PODS -eq 0 ] && [ $VMS -eq 0 ] && [ $DEPLOYMENTS -eq 0 ]; then
            echo "  ⚠️  Nenhum recurso criado ainda - verificando problemas..."
            
            # Verificar eventos de erro
            echo "  Eventos recentes:"
            oc get events -n $ns --sort-by=.metadata.creationTimestamp | tail -3
            
            # Verificar status da application
            APP_NAME="vm-infrastructure-${ns#vm-}"
            if oc get application $APP_NAME -n argocd &>/dev/null; then
                SYNC_STATUS=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.sync.status}')
                HEALTH_STATUS=$(oc get application $APP_NAME -n argocd -o jsonpath='{.status.health.status}')
                echo "  Application Status: Sync=$SYNC_STATUS, Health=$HEALTH_STATUS"
            fi
        else
            echo "  ✅ Recursos criados com sucesso!"
        fi
        echo
    fi
done

# ============================================
# 8. RELATÓRIO FINAL
# ============================================
echo
echo "📋 === 8. RELATÓRIO FINAL ==="

# Verificar ApplicationSet
if oc get applicationset vm-infrastructure-set -n argocd &>/dev/null; then
    echo "✅ ApplicationSet: vm-infrastructure-set criado"
else
    echo "❌ ApplicationSet: vm-infrastructure-set NÃO criado"
fi

# Verificar Applications
TOTAL_APPS=$(oc get applications -n argocd | grep vm-infrastructure | wc -l)
echo "✅ Applications criadas: $TOTAL_APPS/3"

# Verificar recursos totais
TOTAL_RESOURCES=0
for ns in vm-dev vm-staging vm-prod; do
    if oc get namespace $ns &>/dev/null; then
        NS_RESOURCES=$(oc get all -n $ns --no-headers 2>/dev/null | wc -l)
        TOTAL_RESOURCES=$((TOTAL_RESOURCES + NS_RESOURCES))
    fi
done

echo "✅ Total de recursos criados: $TOTAL_RESOURCES"

# Status GitOps
if [ $TOTAL_RESOURCES -gt 0 ]; then
    echo "🎉 SUCESSO: GitOps funcionando - recursos sendo criados!"
else
    echo "⚠️  PROBLEMA: Recursos não estão sendo criados"
    echo "   Próximos passos:"
    echo "   1. Verificar logs: argocd app logs vm-infrastructure-dev"
    echo "   2. Verificar kustomize: kustomize build environments/dev"
    echo "   3. Verificar OpenShift Virtualization"
fi

echo
echo "🎯 === CORREÇÃO COMPLETA FINALIZADA ==="
echo
echo "📝 Comandos úteis:"
echo "  - Ver applications: oc get applications -n argocd"
echo "  - Ver recursos: oc get all,vm,dv -n vm-dev"
echo "  - Ver logs ArgoCD: argocd app logs vm-infrastructure-dev"
echo "  - Dashboard ArgoCD: https://$ARGOCD_URL"
