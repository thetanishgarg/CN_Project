#!/bin/bash
# Re-creates every file derived from the 22 Nov capture (evidence/05-wireshark/full-flow.pcap):
# the filtered capture, the decoded ladders and the server certificate.
#   ./evidence/build/decode-pcap.sh            write next to the originals
#   OUT=/tmp/x ./evidence/build/decode-pcap.sh write somewhere else (to compare)
# Needs Wireshark's tshark (the app bundle path below, or tshark on PATH).
set -e
cd "$(dirname "$0")/../.."
TS=$(command -v tshark || echo /Applications/Wireshark.app/Contents/MacOS/tshark)
IN=evidence/05-wireshark/full-flow.pcap
OUT="${OUT:-evidence}"; mkdir -p "$OUT/05-wireshark" "$OUT/03-https"
W="$OUT/05-wireshark"; T="$W/team-traffic-only.pcap"
EDGE=10.202.54.225   # edge address of the 22 Nov network, taken from the capture's own DNS answer

# 1. keep only team traffic: our DNS names and the HTTPS edge, drop unrelated background traffic
$TS -r $IN -Y "(dns.qry.name contains \"team1.test\" || (tcp.port==443 && ip.addr==$EDGE))" -w "$T" -F pcap
# 2. decoded views used as figures
{ echo "# evidence/05-wireshark/team-traffic-only.pcap"; echo "\$ tshark -Y dns"; $TS -r "$T" -Y dns; echo; echo "\$ tshark -Y tcp.port==64537"; $TS -r "$T" -Y tcp.port==64537; } > "$W/packet-ladder-tls12.txt"
{ echo "\$ tshark -Y tcp.port==64538   (TLS 1.3)"; $TS -r "$T" -Y tcp.port==64538; } > "$W/packet-ladder-tls13.txt"
{ echo "\$ tshark -O dns  (frame: response)"; $TS -r "$T" -O dns -Y 'dns.a'; } > "$W/dns-response-decoded.txt"
$TS -r "$T" -O eth,ip,tcp,tls -Y 'tcp.port==64537 && tls.handshake.type==1' > "$W/clienthello-decoded.txt"
$TS -r "$T" -q -z conv,tcp > "$W/tcp-conversations.txt"
# 3. the server certificate, sent in clear by TLS 1.2 (first certificate of the first Certificate message)
$TS -r $IN -Y 'tls.handshake.type==11 && ip' -T fields -e tls.handshake.certificate | head -1 | cut -d, -f1 | tr -d ':' | xxd -r -p > "$OUT/03-https/.cert.der"
openssl x509 -inform DER -in "$OUT/03-https/.cert.der" -out "$OUT/03-https/server-cert-from-capture.pem"; rm "$OUT/03-https/.cert.der"
echo "wrote $T and the decoded files under $OUT/"
