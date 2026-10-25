#!/bin/sh
# Runs INSIDE the uptime-check container (curlimages/curl, mounted at
# /usr/local/bin/uptime-check). Every CHECK_INTERVAL_SECONDS it requests
# https://$PUBLIC_HOST/health/<svc>/ready for each svc in CHECK_SERVICES, going
# the same way a client on this machine does: the published port (CHECK_VIA,
# default host.docker.internal:443 = this Mac's 127.0.0.1:443) → Docker's port
# forwarding → gateway → service, with the same host name and TLS.
#   Logs (JSON): ERROR when a service goes down, WARNING on each further failed
#   check, INFO when it comes back. Nothing while all is well.
#   Container health: "healthy" only while every service answered 200 on the last round,
#   so `docker compose ps` shows the state of the whole path at a glance.
set -u
host="${PUBLIC_HOST:-localhost}"
interval="${CHECK_INTERVAL_SECONDS:-60}"
services="${CHECK_SERVICES:-articles users}"
via="${CHECK_VIA:-host.docker.internal:443}"

# Verify the gateway's certificate with mkcert's CA when certs/ has it;
# otherwise the gateway serves its self-signed default, which can't be verified.
if [ -f /certs/rootCA.pem ]; then tls="--cacert /certs/rootCA.pem"; verified=true
else tls="--insecure"; verified=false; fi

log() { echo "{\"level\":\"$1\",\"message\":\"$2\",\"service\":\"$3\",\"status\":\"$4\",\"http_code\":\"$5\",\"seconds\":\"$6\",\"tls_verified\":$verified}"; }

trap 'exit 0' TERM INT
echo "{\"level\":\"INFO\",\"message\":\"uptime-check started\",\"services\":\"$services\",\"via\":\"$via\",\"interval_seconds\":$interval,\"tls_verified\":$verified}"
while true; do
  all_up=true
  for svc in $services; do
    # --connect-to: open the TCP connection to $via, but keep https://$host as
    # the URL, so the Host header and TLS name match a real client's.
    result=$(curl -s -o /dev/null --max-time 5 $tls \
      --connect-to "$host:443:$via" \
      -w '%{http_code} %{time_total}' "https://$host/health/$svc/ready")
    code=${result% *}; secs=${result#* }
    previous=$(cat "/tmp/state-$svc" 2>/dev/null || echo unknown)
    if [ "$code" = 200 ]; then
      [ "$previous" = down ] && log INFO "service is back up" "$svc" up "$code" "$secs"
      echo up > "/tmp/state-$svc"
    else
      all_up=false
      if [ "$previous" != down ]; then log ERROR "service is down" "$svc" down "$code" "$secs"
      else log WARNING "service still down" "$svc" down "$code" "$secs"; fi
      echo down > "/tmp/state-$svc"
    fi
  done
  if $all_up; then touch /tmp/all-up; else rm -f /tmp/all-up; fi
  sleep "$interval" & wait $!
done
