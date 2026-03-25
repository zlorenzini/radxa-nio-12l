#!/usr/bin/env bash
# Scan subnet for the NIO 12L (hostname mtk-genio) using password SSH
PW="N1oTwelve!!"
TARGETS=$(nmap -sn 192.168.0.0/24 -oG - 2>/dev/null | grep Up | awk '{print $2}' | grep -v 192.168.0.102)

for ip in $TARGETS; do
  result=$(expect << EOEXP 2>/dev/null
set timeout 5
spawn ssh -o StrictHostKeyChecking=no -o ConnectTimeout=4 ubuntu@$ip
expect {
  "password:" { send "$PW\r"; exp_continue }
  "\$ "       { send "hostname\r" }
  timeout     { exit 1 }
  eof         { exit 1 }
}
expect "\$ "
send "exit\r"
expect eof
EOEXP
)
  if echo "$result" | grep -q 'mtk-genio'; then
    echo "FOUND: $ip"
    exit 0
  fi
done
echo "NOT FOUND"
