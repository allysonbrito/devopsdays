#!/bin/bash
# scripts/fix-patches.sh - CORREÇÃO RÁPIDA DOS PATCHES

echo "🔧 Corrigindo estrutura de patches..."

# Verificar se estamos no diretório correto
if [[ $(basename $(pwd)) != "vm-infrastructure" ]]; then
    echo "❌ Execute dentro do diretório vm-infrastructure"
    exit 1
fi

# Corrigir kustomization.yaml de cada ambiente
echo "Corrigindo kustomization.yaml dos ambientes..."

for env in dev staging prod; do
    echo "Corrigindo $env..."
    
    cat > environments/$env/kustomization.yaml << EOF
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization

namespace: vm-$env

resources:
- ../../base

patches:
- path: vm-config.yaml
- path: datavolume-config.yaml
- path: container-config.yaml

namePrefix: $env-

labels:
- pairs:
    environment: $env
    version: v1.0.0

images:
- name: quay.io/techlead_allyson/hybrid-web-frontend
  newTag: latest
- name: quay.io/techlead_allyson/hybrid-api-backend
  newTag: latest
EOF
done

# Separar vm-config.yaml em dois arquivos para DEV
echo "Criando patches separados para DEV..."

# Backup se existir
if [[ -f environments/dev/vm-config.yaml ]]; then
    cp environments/dev/vm-config.yaml environments/dev/vm-config.yaml.bak
fi

# VM Config apenas (sem DataVolume)
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
EOF

# DataVolume Config separado
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

# Container Config (se não existir)
if [[ ! -f environments/dev/container-config.yaml ]]; then
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
fi

# Criar arquivos para STAGING
echo "Criando patches para STAGING..."

cat > environments/staging/vm-config.yaml << 'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-app
spec:
  template:
    spec:
      domain:
        cpu:
          cores: 3
        memory:
          guest: 6Gi
        resources:
          requests:
            memory: 6Gi
            cpu: 3
      volumes:
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: admin
            password: staging123
            chpasswd: { expire: False }
            ssh_pwauth: True
            package_update: true
            packages:
              - nginx
              - htop
            runcmd:
              - systemctl enable nginx
              - systemctl start nginx
              - echo "STAGING Environment - GitOps Managed VM - Version: 2.0" > /var/www/html/index.html
              - echo "Connected to VM Infrastructure" >> /var/www/html/index.html
              - firewall-cmd --permanent --add-service=http
              - firewall-cmd --reload
EOF

cat > environments/staging/datavolume-config.yaml << 'EOF'
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: vm-app-rootdisk
spec:
  pvc:
    resources:
      requests:
        storage: 20Gi
EOF

cat > environments/staging/container-config.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: frontend
        resources:
          requests:
            memory: "128Mi"
            cpu: "100m"
          limits:
            memory: "256Mi"
            cpu: "200m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
spec:
  replicas: 2
  template:
    spec:
      containers:
      - name: backend
        env:
        - name: ENVIRONMENT
          value: "staging"
        - name: NAMESPACE
          value: "vm-staging"
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "400m"
EOF

# Criar arquivos para PROD
echo "Criando patches para PROD..."

cat > environments/prod/vm-config.yaml << 'EOF'
apiVersion: kubevirt.io/v1
kind: VirtualMachine
metadata:
  name: vm-app
spec:
  template:
    spec:
      domain:
        cpu:
          cores: 4
        memory:
          guest: 8Gi
        resources:
          requests:
            memory: 8Gi
            cpu: 4
      volumes:
      - name: cloudinitdisk
        cloudInitNoCloud:
          userData: |
            #cloud-config
            user: admin
            password: prod123
            chpasswd: { expire: False }
            ssh_pwauth: True
            package_update: true
            packages:
              - nginx
              - htop
              - curl
            runcmd:
              - systemctl enable nginx
              - systemctl start nginx
              - echo "PRODUCTION Environment - GitOps Managed VM - Version: 3.0" > /var/www/html/index.html
              - echo "Connected to VM Infrastructure" >> /var/www/html/index.html
              - firewall-cmd --permanent --add-service=http
              - firewall-cmd --reload
EOF

cat > environments/prod/datavolume-config.yaml << 'EOF'
apiVersion: cdi.kubevirt.io/v1beta1
kind: DataVolume
metadata:
  name: vm-app-rootdisk
spec:
  pvc:
    resources:
      requests:
        storage: 50Gi
EOF

cat > environments/prod/container-config.yaml << 'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: web-frontend
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: frontend
        resources:
          requests:
            memory: "256Mi"
            cpu: "200m"
          limits:
            memory: "512Mi"
            cpu: "400m"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-backend
spec:
  replicas: 3
  template:
    spec:
      containers:
      - name: backend
        env:
        - name: ENVIRONMENT
          value: "prod"
        - name: NAMESPACE
          value: "vm-prod"
        resources:
          requests:
            memory: "512Mi"
            cpu: "400m"
          limits:
            memory: "1Gi"
            cpu: "800m"
EOF

echo "✅ Patches corrigidos!"

# Testar build em cada ambiente
echo "🧪 Testando build em cada ambiente..."
for env in dev staging prod; do
    echo "Testando $env..."
    if kustomize build environments/$env > /tmp/test-$env.yaml 2>/dev/null; then
        RESOURCES=$(grep -c "^kind:" /tmp/test-$env.yaml)
        VMS=$(grep -c "kind: VirtualMachine" /tmp/test-$env.yaml)
        DEPLOYMENTS=$(grep -c "kind: Deployment" /tmp/test-$env.yaml)
        DATAVOLUMES=$(grep -c "kind: DataVolume" /tmp/test-$env.yaml)
        echo "  ✅ $env: $RESOURCES recursos ($VMS VMs, $DATAVOLUMES DVs, $DEPLOYMENTS Deployments)"
    else
        echo "  ❌ $env: ERRO no build"
        kustomize build environments/$env 2>&1 | head -3
    fi
done

echo
echo "🎯 === CORREÇÃO CONCLUÍDA ==="
echo "Agora os patches estão separados corretamente:"
echo "- vm-config.yaml (apenas VirtualMachine)"
echo "- datavolume-config.yaml (apenas DataVolume)"
echo "- container-config.yaml (Deployments)"
echo
echo "Execute: git add . && git commit -m 'fix: separate patch files for kustomize'"
