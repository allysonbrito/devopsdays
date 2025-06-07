#!/usr/bin/env bash
set -euo pipefail

# Quantidade de VMs a criar
VM_COUNT=2

# 1. Descobre o maior índice já existente em dev*.yaml ou Dev*.yaml
max=0
for f in [dD]ev*.yaml; do
  [[ -e "$f" ]] || continue
  n=${f#*[dD]ev}; n=${n%.yaml}
  [[ $n =~ ^[0-9]+$ ]] && (( n > max )) && max=$n
done

# 2. Define intervalo de geração com base em VM_COUNT
start=$(( max + 1 ))
end=$(( start + VM_COUNT - 1 ))
template="dev3.yaml"

# 3. Gera novas manifests e atualiza kustomization.yaml
for i in $(seq "$start" "$end"); do
  out="dev${i}.yaml"
  [[ -f $out ]] && { echo "Já existe $out, pulando"; continue; }

  # substitui todas as ocorrências de "dev3" ou "Dev3" por "dev${i}"
  sed -E \
    -e "s/[dD]ev3/dev${i}/g" \
    "$template" > "$out"
  echo "Gerado $out"

  # adiciona ao kustomization.yaml se ainda não estiver
  if ! grep -qx "  - ${out}" kustomization.yaml; then
    sed -i '' "/^resources:/a\\
  - ${out}
" kustomization.yaml
    echo "Adicionado ${out} em kustomization.yaml"
  fi
done

