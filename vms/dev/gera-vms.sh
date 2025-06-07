#!/usr/bin/env bash
set -euo pipefail

# Quantidade de VMs a criar
VM_COUNT=2

# 1. Descobre o maior índice já existente em dev*.yaml
max=0
for f in dev*.yaml; do
  [[ -e "$f" ]] || continue
  n=${f#dev}; n=${n%.yaml}
  [[ $n =~ ^[0-9]+$ ]] && (( n > max )) && max=$n
done

# 2. Define intervalo de geração com base em VM_COUNT
start=$(( max + 1 ))
end=$(( start + VM_COUNT - 1 ))
template="dev2.yaml"

# 3. Gera as novas manifests e atualiza kustomization.yaml (macOS sed)
for i in $(seq "$start" "$end"); do
  out="dev${i}.yaml"
  if [[ -f $out ]]; then
    echo "Já existe $out, pulando"
    continue
  fi

  sed \
    -e "s/name: dev2/name: dev${i}/g" \
    -e "s/kubevirt.io\\/domain: dev2/kubevirt.io\\/domain: dev${i}/g" \
    -e "s/hostname: dev2/hostname: dev${i}/g" \
    "$template" > "$out"
  echo "Gerado $out"

  if ! grep -qx "  - ${out}" kustomization.yaml; then
    sed -i '' "/^resources:/a\\
  - ${out}
" kustomization.yaml
    echo "Adicionado ${out} em kustomization.yaml"
  fi
done
