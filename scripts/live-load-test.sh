#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-http://178.170.25.235}"
DURATION_SECONDS="${DURATION_SECONDS:-60}"
CONCURRENCY="${CONCURRENCY:-20}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-10}"
PRINT_EVERY_SECONDS="${PRINT_EVERY_SECONDS:-5}"
K8S_NAMESPACE="${K8S_NAMESPACE:-worldcup}"
SHOW_K8S="${SHOW_K8S:-1}"

RESULTS_FILE="$(mktemp)"
START_TS="$(date +%s)"
END_TS="$((START_TS + DURATION_SECONDS))"

cleanup() {
  rm -f "$RESULTS_FILE"
}
trap cleanup EXIT

paths=(
  "/"
  "/api/health"
  "/api/health/db"
  "/api/teams"
  "/api/groups"
  "/api/matches"
  "/api/standings"
  "/api/votes/results"
  "/metrics"
)

echo "Live load test"
echo "target      : $TARGET_URL"
echo "duration    : ${DURATION_SECONDS}s"
echo "concurrency : $CONCURRENCY"
echo "timeout     : ${REQUEST_TIMEOUT}s"
echo

for worker in $(seq 1 "$CONCURRENCY"); do
  (
    index="$worker"
    while [ "$(date +%s)" -lt "$END_TS" ]; do
      path="${paths[$((index % ${#paths[@]}))]}"
      curl -sS -o /dev/null \
        --max-time "$REQUEST_TIMEOUT" \
        -w "%{http_code} %{time_total}\n" \
        "${TARGET_URL}${path}" >> "$RESULTS_FILE" 2>/dev/null || echo "000 0" >> "$RESULTS_FILE"
      index="$((index + 1))"
    done
  ) &
done

while [ "$(date +%s)" -lt "$END_TS" ]; do
  sleep "$PRINT_EVERY_SECONDS"
  now="$(date +%s)"
  elapsed="$((now - START_TS))"

  awk -v elapsed="$elapsed" '
    {
      total++;
      if ($1 >= 200 && $1 < 400) ok++;
      else errors++;
      latency += $2;
    }
    END {
      if (total == 0) {
        printf("t+%ss | requests=0\n", elapsed);
      } else {
        printf("t+%ss | requests=%d | ok=%d | errors=%d | rps=%.2f | avg_latency=%.3fs\n",
          elapsed, total, ok, errors, total / elapsed, latency / total);
      }
    }
  ' "$RESULTS_FILE"

  if [ "$SHOW_K8S" = "1" ] && command -v kubectl >/dev/null 2>&1; then
    kubectl get hpa -n "$K8S_NAMESPACE" 2>/dev/null || true
    kubectl get pods -n "$K8S_NAMESPACE" -l app.kubernetes.io/name=worldcup-app 2>/dev/null || true
  fi
done

wait

echo
echo "Final summary"
awk '
  {
    total++;
    codes[$1]++;
    if ($1 >= 200 && $1 < 400) ok++;
    else errors++;
    latency += $2;
    if ($2 > max) max = $2;
  }
  END {
    if (total == 0) {
      print "No request completed.";
      exit 1;
    }

    printf("requests    : %d\n", total);
    printf("success     : %d\n", ok);
    printf("errors      : %d\n", errors);
    printf("avg latency : %.3fs\n", latency / total);
    printf("max latency : %.3fs\n", max);
    print "status codes:";
    for (code in codes) {
      printf("  %s: %d\n", code, codes[code]);
    }

    if (errors > 0) {
      exit 2;
    }
  }
' "$RESULTS_FILE"
