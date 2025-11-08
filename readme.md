# Protocolo de Infraestrutura e Testes — Sec 365

**Equipe Kleber**
Kleber Vilhena, Andrey, Ivan Neves, Lucas, Delvek, Carlos, Cassia

---

## Sumário

1. [Visão Geral](#visão-geral)
2. [Requisitos](#requisitos)
3. [Tutorial — Varredura básica (Nmap)](#tutorial---varredura-básica-nmap)
4. [Fase 1 — Pentest Wireless (cenários)](#fase-1---pentest-wireless-cenários)
   4.1 [Teste de Confiança do Dispositivo (Karma)](#teste-de-confiança-do-dispositivo-karma)
   4.2 [Phishing em Rede Local (Rogue AP + DNS Spoofing)](#phishing-em-rede-local-rogue-ap--dns-spoofing)
   4.3 [Política de Segurança Física (BadUSB)](#política-de-segurança-física-badusb)
   4.4 [Política de Inatividade (Mouse Jiggler)](#política-de-inatividade-mouse-jiggler)
5. [Fase 2 — White-box Pentest (camada de aplicação)](#fase-2---white-box-pentest-camada-de-aplicação)
   5.1 [Objetivo e estrutura](#objetivo-e-estrutura)
   5.2 [Ambiente de laboratório](#ambiente-de-laboratório)
   5.3 [Vulnerabilidades exploradas](#vulnerabilidades-exploradas)
6. [Ferramentas auxiliares](#ferramentas-auxiliares)
7. [Pentest — Client Mode (procedimentos e comandos)](#pentest---client-mode-procedimentos-e-comandos)
8. [Checklist rápido](#checklist-rápido)
9. [Coleta de evidências e empacotamento](#coleta-de-evidências-e-empacotamento)
10. [Observações técnicas e de risco](#observações-técnicas-e-de-risco)

---

## Visão geral

Documento técnico com procedimentos práticos para avaliação de infraestrutura e aplicação em ambiente controlado (Sec 365). Todas as ações devem ser autorizadas pelo responsável da rede/ambiente antes de execução.

---

## Requisitos

* PC com Kali Linux
* M5Stack (evil card / card computer)
* VirtualBox (para laboratório: Kali + Bee-box/bWAPP)

---

## Tutorial — Varredura básica (Nmap)

Confirme o range de IPs antes de varrer.

Comandos de exemplo:

```bash
ip -a
sudo nmap -sS -p- -sV 172.20.10.0/28 -oN varredura_completa.txt
sudo nmap -sS -sV 172.20.10.1 -oN varredura_gateway_rapida.txt
```

Exemplo: varredura focada em porta e extração de banner:

```bash
telnet 172.20.10.1 21
sudo nmap -p 21 --script banner 172.20.10.1 -oN banner_ftp_21.txt
sudo nmap -p 80,443 -sV 172.20.10.1 -oN varredura_web_gateway.txt
```

Brute-force FTP (exemplo) — crie wordlist no home:

```bash
cd ~
echo "senha" > wordlist.txt
echo "123456" >> wordlist.txt
echo "admin" >> wordlist.txt
echo "password" >> wordlist.txt
sudo hydra -P wordlist.txt 172.20.10.1 ftp -t 4
```

Wireless (modo monitor / captura handshake):

```bash
sudo airmon-ng check kill
sudo airmon-ng start wlan0
sudo airodump-ng wlan0mon
sudo aireplay-ng -0 10 -a <MAC_ROUTER> wlan0mon
sudo airodump-ng --bssid <MAC_ROUTER> -w <SSID>-cap -c <CHANNEL> wlan0mon
```

Tabela de porta/serviço (exemplo):

```
PORTA   ESTADO  SERVIÇO     OBSERVAÇÃO
21/tcp  open    ftp         ALTO RISCO POTENCIAL
53/tcp  open    domain      DNS (roteador)
49152   open    tcpwrapped  porta alta
```

---

## Fase 1 — Pentest Wireless (cenários)

### Teste de Confiança do Dispositivo (Ataque Karma)

* **Ataque:** Probe sniffing → Karma Spear Attack
* **Objetivo:** verificar se dispositivos se conectam automaticamente a APs falsos
* **Passos:** capturar probes, gerar karma file com SSIDs, anunciar com card computer, observar conexões automáticas
* **Remediação:** esquecer SSIDs antigos, desabilitar conexão automática

### Teste de Phishing em Rede Local

* **Ataque:** Rogue AP + DNS spoofing (Man-in-the-Middle)
* **Objetivo:** redirecionar tráfego HTTP/HTTPS (teste em ambiente controlado)
* **Passos:** criar Rogue AP, conectar dispositivo de teste, ativar DNS spoofing, servir página de phishing controlada
* **Remediação:** uso de VPN, verificação de HTTPS/EV, HSTS, educação do usuário


### Teste de Política de Inatividade (Mouse Jiggler)

* **Ataque:** dispositivo que simula atividade (evita bloqueio)
* **Objetivo:** validar políticas de bloqueio/suspensão
* **Passos:** configurar bloqueio para 5 minutos, conectar mouse jiggler, monitorar comportamento
* **Remediação:** ajustes de políticas de energia e bloqueio, controle de acesso físico

---

## Fase 2 — White-box Pentest (camada de aplicação)

### Objetivo e estrutura

Foco em vulnerabilidades web comuns. Teste contido em laboratório com duas VMs (Atacante + Alvo). Procedimento orientado para identificar, explorar e mitigar.

### Ambiente de laboratório

* Máquina atacante: Kali (sqlmap, nmap, Burp, Hydra, netcat)
* Máquina alvo: Bee-box / bWAPP (vulnerável por design)
* Rede: interna/bridge entre VMs

### Vulnerabilidades exploradas

* **SQL Injection (SQLi)** — usar sqlmap (`--dbs`, `--tables`, `--columns`, `--dump`). Correção: prepared statements + validação.
* **Unrestricted File Upload** — upload de reverse shell + netcat listener. Correção: whitelist de extensões e validação de magic bytes.
* **LFI (Local File Inclusion)** — path traversal (`../..`) para ler `/etc/passwd`. Correção: não concatenar caminhos com input, whitelist.
* **XSS Stored** — injeção de `<script>` em campos persistentes. Correção: sanitização e escaping.
* **Insecure FTP Configuration** — login anônimo. Correção: desativar anonymous, usar SFTP/FTPS.
* **Broken Authentication (Brute Force)** — Burp Intruder / Hydra; mitigar com lockout, rate limiting, MFA.

---

## Ferramentas auxiliares (confirmar versão final)

* **John the Ripper** — quebra de hashes (zip2john, rar2john)
* **Netcat (nc)** — listener para reverse shells (`nc -lvp 4444`)
* **Hydra** — força bruta multi-protocolo (FTP, SSH, etc.)

---

## Pentest — Client Mode (procedimentos e comandos)

### 5.1 Workspace

```bash
cd ~
mkdir -p ~/pentest/$(date +%F)_wifi/evidence
```

### 5.2 Informação local (interface, gateway, subnet)

```bash
ip -4 -o addr show scope global
ip route show
SUBNET=$(ip -4 -o addr show scope global | awk '{print $4}' | head -n1)
GATEWAY=$(ip route show default | awk '{print $3}')
echo $SUBNET $GATEWAY
```

### 5.3 Descoberta de hosts (sem sudo preferível)

```bash
nmap -sT --top-ports 200 -T4 $SUBNET -oN evidence/nmap_top.txt
grep -oP 'Nmap scan report for \K[\d.]+' evidence/nmap_top.txt | sort -u > evidence/hosts.txt
# opcional (sudo):
sudo arp-scan --localnet --interface wlan0 > evidence/arp-scan.txt
```

### 5.4 Enumeração de serviços por host

Sem sudo:

```bash
nmap -sT -sV -iL evidence/hosts.txt --top-ports 200 -oA evidence/nmap_services
```

Com sudo (mais completo):

```bash
sudo nmap -sS -sV -iL evidence/hosts.txt -p- -T4 --min-rate 500 -oA evidence/nmap_syn_full
```

### 5.5 Checar serviços web (HTTP/HTTPS)

```bash
while read -r H; do
  curl -I --max-time 5 http://$H:80 2>/dev/null | sed -n '1p' >> evidence/http_status.txt || true
done < evidence/hosts.txt

while read -r H; do
  nikto -host http://$H -output evidence/nikto_$H.txt 2>/dev/null || true
done < evidence/hosts.txt

while read -r H; do
  dirb http://$H /usr/share/wordlists/dirb/common.txt -o evidence/dirb_$H.txt || true
done < evidence/hosts.txt
```

### 5.6 Testar autenticação / captive portals

```bash
curl -I --max-time 5 http://detectportal.firefox.com/ || true
curl -s --max-time 8 http://$GATEWAY/ | head -n 40 > evidence/gateway_home.html || true
```

### 5.7 Captura de tráfego local (requer sudo)

```bash
sudo tcpdump -i wlan0 -s 0 -w evidence/capture.pcap   # pare com Ctrl+C

tshark -r evidence/capture.pcap -q -z conv,ip > evidence/tshark_conv_ip.txt
tshark -r evidence/capture.pcap -Y "http.request" -T fields -e ip.src -e http.host -e http.request.uri > evidence/http_requests.txt

# Alternativa para interceptar browser (requer configurar CA):
mitmproxy --listen-port 8080 -w evidence/mitmflow.log
```

### 5.8 MITM / ARP spoof (requer autorização e sudo)

```bash
sudo bettercap -iface wlan0
# dentro do bettercap:
# net.probe on
# net.sniff on
# arp.spoof on
```

### 5.9 Testes cliente-a-cliente / isolamento

```bash
while read -r H; do
  ping -c1 -W1 $H >/dev/null && echo "$H up" || true
done < evidence/hosts.txt

while read -r H; do
  nmap -sT -p 22,80,139,445 -oN evidence/scan_$H.txt $H || true
done < evidence/hosts.txt
```

### 5.10 Enumeração SMB/Windows (se presentes)

```bash
smbclient -L //$TARGET -N
enum4linux -a $TARGET > evidence/enum4linux_$TARGET.txt
```

### 5.11 SNMP / IoT checks

```bash
snmpwalk -v2c -c public $TARGET 1 > evidence/snmp_$TARGET.txt 2>/dev/null || true
sudo nmap -sU -p 161 -iL evidence/hosts.txt -oA evidence/nmap_udp
```

### 5.12 Testes de autenticação / brute force (SOMENTE AUTORIZADO)

```bash
hydra -L users.txt -P passwords.txt ssh://$TARGET -t 4 -w 5 -f -o evidence/hydra_ssh_$TARGET.txt
```

### 5.13 Coleta de evidências e empacotamento

```bash
tar czf evidence_$(date +%F_%H%M%S).tgz evidence/
```

---

## Checklist rápido (quando conectado como cliente)

* Identificar SUBNET e GATEWAY.
* Descobrir hosts (nmap -sT; arp-scan se autorizado).
* Mapear serviços (nmap -sT/-sV; -sS se sudo).
* Checar web (curl, nikto, dirb).
* Verificar client isolation (ping + nmap em hosts).
* Capturar tráfego (tcpdump com sudo / mitmproxy para browser).
* Testar SMB / IoT / SNMP.
* MITM/ARP spoof só se no escopo e autorizado.
* Coletar e empacotar evidências.

---

## Coleta de evidências e empacotamento

* Organizar evidências em `~/pentest/<data>_wifi/evidence`
* Incluir: outputs do nmap, captures pcap, logs de ferramentas, screenshots, relatório de passos executados.
* Empacotar com `tar czf evidence_<timestamp>.tgz evidence/`

---

## Observações técnicas e de risco — direto

* Sempre obter autorização por escrito antes de qualquer teste.
* Operações com impacto (DoS, MITM, brute-force) só no escopo explicitamente autorizado.
* Registre data/hora, comandos exatos e saída de cada etapa para rastreabilidade.
* Priorize segurança do ambiente de testes (lab isolado) para evitar impacto externo.

---

## Contato / Responsável

* Equipe Kleber (ver header).
* Em caso de dúvidas ou para autorizações: contatar o responsável técnico antes de executar qualquer procedimento.

---

Fim.

Se quiser, eu gero um `README.md` pronto com esse conteúdo para salvar no repositório. Quer que eu gere o arquivo agora?
