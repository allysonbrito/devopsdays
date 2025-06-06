#!/bin/bash
# scripts/setup-complete.sh - VERSÃO CONSOLIDADA COM TODAS AS CORREÇÕES

set -e

echo "🚀 === SETUP COMPLETO VM-INFRASTRUCTURE GITOPS ==="
echo "Repository: https://github.com/allysonbrito/devopsdays.git"
echo "Registry: quay.io/techlead_allyson"
echo "Base Path: vm-infrastructure"
echo

# Variáveis configuradas
export REGISTRY="quay.io/techlead_allyson"
export GIT_REPO="https://github.com/allysonbrito/devopsdays.git"
export BASE_PATH="vm-infrastructure"

# Verificar se estamos no diretório correto
if [[ $(basename $(pwd)) != "vm-infrastructure" ]]; then
    echo "❌ Execute este script dentro do diretório vm-infrastructure"
    echo "Diretório atual: $(pwd)"
    echo "Comando correto: cd devopsdays/vm-infrastructure && ./scripts/setup-complete.sh"
    exit 1
fi

echo "✅ Diretório correto detectado: $(pwd)"
echo

# 1. CRIAR ESTRUTURA DE DIRETÓRIOS
echo "📁 Criando estrutura de diretórios..."
mkdir -p {applications,environments/{dev,staging,prod},base/{vm,containers},docker/{web-frontend,api-backend},scripts}
echo "✅ Estrutura criada"

# 2. CRIAR KUSTOMIZATION FILES (SINTAXE ATUALIZADA)
echo "🔧 Criando arquivos kustomization.yaml com sintaxe atualizada..."

# Base principal
cat > base/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- vm/
- containers/

labels:
- pairs:
    managed-by: argocd
    infrastructure: vm-platform
EOF

# Base VM
cat > base/vm/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- vm-template.yaml

labels:
- pairs:
    managed-by: argocd
    infrastructure: vm-platform
    component: virtualization
EOF

# Base Containers
cat > base/containers/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

resources:
- web-frontend.yaml
- api-backend.yaml

labels:
- pairs:
    managed-by: argocd
    infrastructure: vm-platform
    component: containers

images:
- name: quay.io/techlead_allyson/hybrid-web-frontend
  newTag: latest
- name: quay.io/techlead_allyson/hybrid-api-backend
  newTag: latest
EOF

# Environment DEV
cat > environments/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: vm-dev

resources:
- ../../base

patches:
- path: vm-config.yaml
  target:
    group: kubevirt.io
    version: v1
    kind: VirtualMachine
    name: vm-app
- path: vm-config.yaml
  target:
    group: cdi.kubevirt.io
    version: v1beta1
    kind: DataVolume
    name: vm-app-rootdisk
- path: container-config.yaml
  target:
    group: apps
    version: v1
    kind: Deployment
    name: web-frontend
- path: container-config.yaml
  target:
    group: apps
    version: v1
    kind: Deployment
    name: api-backend

namePrefix: dev-

labels:
- pairs:
    environment: dev
    version: v1.0.0

images:
- name: quay.io/techlead_allyson/hybrid-web-frontend
  newTag: latest
- name: quay.io/techlead_allyson/hybrid-api-backend
  newTag: latest
EOF

# Environment STAGING
cat > environments/staging/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: vm-staging

resources:
- ../../base

patches:
- path: vm-config.yaml
  target:
    group: kubevirt.io
    version: v1
    kind: VirtualMachine
    name: vm-app
- path: vm-config.yaml
  target:
    group: cdi.kubevirt.io
    version: v1beta1
    kind: DataVolume
    name: vm-app-rootdisk
- path: container-config.yaml
  target:
    group: apps
    version: v1
    kind: Deployment
    name: web-frontend
- path: container-config.yaml
  target:
    group: apps
    version: v1
    kind: Deployment
    name: api-backend

namePrefix: staging-

labels:
- pairs:
    environment: staging
    version: v1.0.0

images:
- name: quay.io/techlead_allyson/hybrid-web-frontend
  newTag: latest
- name: quay.io/techlead_allyson/hybrid-api-backend
  newTag: latest
EOF

# Environment PROD
cat > environments/prod/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: vm-prod

resources:
- ../../base

patches:
- path: vm-config.yaml
  target:
    group: kubevirt.io
    version: v1
    kind: VirtualMachine
    name: vm-app
- path: vm-config.yaml
  target:
    group: cdi.kubevirt.io
    version: v1beta1
    kind: DataVolume
    name: vm-app-rootdisk
- path: container-config.yaml
  target:
    group: apps
    version: v1
    kind: Deployment
    name: web-frontend
- path: container-config.yaml
  target:
    group: apps
    version: v1
    kind: Deployment
    name: api-backend

namePrefix: prod-

labels:
- pairs:
    environment: prod
    version: v1.0.0

images:
- name: quay.io/techlead_allyson/hybrid-web-frontend
  newTag: latest
- name: quay.io/techlead_allyson/hybrid-api-backend
  newTag: latest
EOF

echo "✅ Arquivos kustomization.yaml criados"

# 3. CRIAR VM TEMPLATE BASE
echo "🖥️  Criando template base da VM..."
cat > base/vm/vm-template.yaml << 'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-app
  namespace: vm-workloads
  labels:
    app: vm-application
    managed-by: argocd
spec:
  running: true
  template:
    metadata:
      labels:
        kubevirt.io/vm: vm-app
    spec:
      domain:
        cpu:
          cores: 2
        memory:
          guest: 4Gi
        devices:
          disks:
          - name: rootdisk
            disk:
              bus: virtio
          - name: cloudinitdisk
            disk:
              bus: virtio
          interfaces:
          - name: default
            masquerade: {}
        resources:
          requests:
            memory: 4Gi
            cpu: 2
      networks:
      - name: default
        pod: {}
      volumes:
      - name: rootdisk
        dataVolume:
          name: vm-app-rootdisk
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: admin
            password: admin123
            chpasswd: { expire: False }
            ssh_pwauth: True
            package_update: true
            packages:
              - nginx
            runcmd:
              - systemctl enable nginx
              - systemctl start nginx
              - echo "VM Provisioned via GitOps - Version: 1.0" > /var/www/html/index.html
              - echo "Connected to VM Infrastructure" >> /var/www/html/index.html
              - firewall-cmd --permanent --add-service=http
              - firewall-cmd --reload
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: vm-app-rootdisk
  namespace: vm-workloads
spec:
  pvc:
    accessModes:
    - ReadWriteOnce
    resources:
      requests:
        storage: 20Gi
  source:
    registry:
      url: docker://registry.redhat.io/rhel8/rhel-guest-image:latest
---
apiVersion: v1
kind: Service
metadata:
  name: vm-app-service
  namespace: vm-workloads
spec:
  selector:
    kubevirt.io/vm: vm-app
  ports:
  - port: 80
    targetPort: 80
    name: http
  - port: 22
    targetPort: 22
    name: ssh
  type: ClusterIP
EOF

echo "✅ VM template criado"

# 4. CRIAR CONTAINER TEMPLATES BASE
echo "📦 Criando templates base dos containers..."

# Web Frontend
cat > base/containers/web-frontend.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
  labels:
    app: web-frontend
    component: frontend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: web-frontend
  template:
    metadata:
      labels:
        app: web-frontend
        component: frontend
    spec:
      containers:
      - name: frontend
        image: quay.io/techlead_allyson/hybrid-web-frontend:latest
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
        readinessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /
            port: 80
          initialDelaySeconds: 15
          periodSeconds: 20
---
apiVersion: v1
kind: Service
metadata:
  name: web-frontend
  labels:
    app: web-frontend
spec:
  selector:
    app: web-frontend
  ports:
  - port: 80
    targetPort: 80
    name: http
  type: ClusterIP
---
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: web-frontend
  labels:
    app: web-frontend
spec:
  to:
    kind: Service
    name: web-frontend
  port:
    targetPort: http
  tls:
    termination: edge
EOF

# API Backend
cat > base/containers/api-backend.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
  labels:
    app: api-backend
    component: backend
spec:
  replicas: 2
  selector:
    matchLabels:
      app: api-backend
  template:
    metadata:
      labels:
        app: api-backend
        component: backend
    spec:
      serviceAccountName: vm-infrastructure-sa
      containers:
      - name: backend
        image: quay.io/techlead_allyson/hybrid-api-backend:latest
        ports:
        - containerPort: 8080
        env:
        - name: NAMESPACE
          valueFrom:
            fieldRef:
              fieldPath: metadata.namespace
        - name: ENVIRONMENT
          value: "dev"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
        readinessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 10
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: api-backend
  labels:
    app: api-backend
spec:
  selector:
    app: api-backend
  ports:
  - port: 8080
    targetPort: 8080
    name: http
  type: ClusterIP
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: vm-infrastructure-sa
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: vm-infrastructure-reader
rules:
- apiGroups: [""]
  resources: ["pods", "services"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["kubevirt.io"]
  resources: ["virtualmachines", "virtualmachineinstances"]
  verbs: ["get", "list", "watch"]
- apiGroups: ["argoproj.io"]
  resources: ["applications"]
  verbs: ["get", "list", "watch"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: vm-infrastructure-reader-binding
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: vm-infrastructure-reader
subjects:
- kind: ServiceAccount
  name: vm-infrastructure-sa
  namespace: vm-dev
EOF

echo "✅ Container templates criados"

# 5. CRIAR PATCH FILES PARA AMBIENTES
echo "🔧 Criando arquivos de configuração por ambiente..."

# DEV VM Config
cat > environments/dev/vm-config.yaml << 'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-app
spec:
  template:
    spec:
      domain:
        cpu:
          cores: 2
        memory:
          guest: 4Gi
        resources:
          requests:
            memory: 4Gi
            cpu: 2
      volumes:
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: admin
            password: admin123
            chpasswd: { expire: False }
            ssh_pwauth: True
            package_update: true
            packages:
              - nginx
            runcmd:
              - systemctl enable nginx
              - systemctl start nginx
              - echo "DEV Environment - GitOps Managed VM - Version: 1.0" > /var/www/html/index.html
              - echo "Connected to VM Infrastructure" >> /var/www/html/index.html
              - firewall-cmd --permanent --add-service=http
              - firewall-cmd --reload
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: vm-app-rootdisk
spec:
  pvc:
    resources:
      requests:
        storage: 10Gi
EOF

# DEV Container Config
cat > environments/dev/container-config.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: frontend
        resources:
          requests:
            memory: "64Mi"
            cpu: "50m"
          limits:
            memory: "128Mi"
            cpu: "100m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
spec:
  replicas: 1
  template:
    spec:
      containers:
      - name: backend
        env:
        - name: ENVIRONMENT
          value: "dev"
        - name: NAMESPACE
          value: "vm-dev"
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
EOF

echo "✅ Configurações de ambiente criadas"

# 6. CRIAR APPLICATION ARGOCD
echo "🔄 Criando ApplicationSet ArgoCD..."
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
        vmCpu: 2
        vmMemory: 4Gi
        storageSize: 10Gi
      - env: staging
        namespace: vm-staging
        vmCpu: 3
        vmMemory: 6Gi
        storageSize: 20Gi
      - env: prod
        namespace: vm-prod
        vmCpu: 4
        vmMemory: 8Gi
        storageSize: 50Gi
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
        - PrunePropagationPolicy=foreground
      ignoreDifferences:
      - group: kubevirt.io
        kind: VirtualMachine
        jsonPointers:
        - /status
EOF

echo "✅ ApplicationSet criado"

# 7. TESTAR KUSTOMIZE BUILD
echo "🧪 Testando build do Kustomize..."
for env in dev staging prod; do
    echo "Testando $env..."
    if kustomize build environments/$env > /tmp/test-$env.yaml 2>/dev/null; then
        RESOURCES=$(grep -c "^kind:" /tmp/test-$env.yaml)
        echo "  ✅ $env: $RESOURCES recursos gerados"
    else
        echo "  ❌ $env: ERRO no build"
        kustomize build environments/$env 2>&1 | head -3
    fi
done

echo
echo "✅ === SETUP COMPLETO FINALIZADO ==="
echo
echo "📋 Próximos passos:"
echo "1. Commit e push:"
echo "   git add ."
echo "   git commit -m 'feat: setup vm-infrastructure with GitOps'"
echo "   git push origin main"
echo
echo "2. Build e push das imagens Docker"
echo "3. Aplicar ApplicationSet no ArgoCD"
echo
echo "🔗 URLs configuradas:"
echo "  Repository: https://github.com/allysonbrito/devopsdays.git"
echo "  Registry: quay.io/techlead_allyson"
echo "  Path: vm-infrastructure/environments/{env}"
