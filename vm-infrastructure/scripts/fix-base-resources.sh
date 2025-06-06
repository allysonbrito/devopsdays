#!/bin/bash
# scripts/fix-base-resources.sh - CORRIGIR RECURSOS BASE

echo "🔧 === CORRIGINDO RECURSOS BASE ==="

# Verificar diretório
if [[ $(basename $(pwd)) != "vm-infrastructure" ]]; then
    echo "❌ Execute dentro do diretório vm-infrastructure"
    exit 1
fi

# Criar estrutura se não existir
mkdir -p base/{vm,containers}
mkdir -p environments/{dev,staging,prod}

echo "✅ Estrutura de diretórios criada"

# CORRIGIR vm-template.yaml (SEM NAMESPACE HARDCODED)
echo "🖥️  Criando vm-template.yaml corrigido..."
cat > base/vm/vm-template.yaml << 'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-app
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
              - echo "VM Provisioned via GitOps - Base Version" > /var/www/html/index.html
              - firewall-cmd --permanent --add-service=http
              - firewall-cmd --reload
---
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: vm-app-rootdisk
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

echo "✅ vm-template.yaml criado (sem namespace hardcoded)"

# CORRIGIR kustomization.yaml do base/vm
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

echo "✅ base/vm/kustomization.yaml corrigido"

# CORRIGIR containers base se não existir
if [[ ! -f "base/containers/web-frontend.yaml" ]]; then
echo "📦 Criando containers base..."

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

cat > base/containers/api-backend.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
  labels:
    app: api-backend
    component: backend
spec:
  replicas: 1
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
          value: "base"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "500m"
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

echo "✅ Containers base criados"
fi

# CORRIGIR kustomization.yaml principal do base
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

echo "✅ base/kustomization.yaml principal corrigido"

# TESTAR BASE ISOLADAMENTE
echo "🧪 Testando build do base..."
if kustomize build base/ > /tmp/base-test.yaml 2>&1; then
    echo "✅ Base build OK!"
    RESOURCES=$(grep -c "^kind:" /tmp/base-test.yaml)
    VMS=$(grep -c "kind: VirtualMachine" /tmp/base-test.yaml)
    DVS=$(grep -c "kind: DataVolume" /tmp/base-test.yaml)
    DEPLOYMENTS=$(grep -c "kind: Deployment" /tmp/base-test.yaml)
    echo "  📊 Base: $RESOURCES recursos ($VMS VMs, $DVS DVs, $DEPLOYMENTS Deployments)"
else
    echo "❌ Base build FAILED"
    echo "Erro:"
    kustomize build base/ 2>&1
    return 1
fi

# CORRIGIR PATCHES PARA SER MAIS SIMPLES
echo "🔧 Corrigindo patches DEV..."

# Patch simples para VM (apenas o que realmente queremos mudar)
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
              - echo "DEV Environment - GitOps Managed VM" > /var/www/html/index.html
              - firewall-cmd --permanent --add-service=http
              - firewall-cmd --reload
EOF

# Patch para DataVolume
cat > environments/dev/datavolume-config.yaml << 'EOF'
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

# Patch para containers
cat > environments/dev/container-config.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
spec:
  replicas: 1
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
EOF

# CORRIGIR kustomization.yaml do DEV
cat > environments/dev/kustomization.yaml << 'EOF'
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: vm-dev

resources:
- ../../base

patches:
- path: vm-config.yaml
- path: datavolume-config.yaml
- path: container-config.yaml

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

echo "✅ DEV patches corrigidos"

# TESTAR BUILD DEV
echo "🧪 Testando build DEV..."
if kustomize build environments/dev/ > /tmp/dev-test.yaml 2>&1; then
    echo "✅ DEV build OK!"
    RESOURCES=$(grep -c "^kind:" /tmp/dev-test.yaml)
    echo "  📊 DEV: $RESOURCES recursos gerados"
else
    echo "❌ DEV build FAILED"
    echo "Erro:"
    kustomize build environments/dev/ 2>&1
fi

echo
echo "🎯 === CORREÇÃO DE BASE CONCLUÍDA ==="
echo "Execute: ./scripts/test-complete.sh para verificar tudo"
