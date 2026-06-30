#!/usr/bin/env bash
set -euo pipefail

TARGET_URL="${TARGET_URL:-http://178.170.25.235}"
DURATION_SECONDS="${DURATION_SECONDS:-180}"
CONCURRENCY="${CONCURRENCY:-40}"
REQUEST_TIMEOUT="${REQUEST_TIMEOUT:-15}"
K8S_NAMESPACE="${K8S_NAMESPACE:-worldcup}"
PRINT_EVERY_SECONDS="${PRINT_EVERY_SECONDS:-10}"
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-60}"

RESULTS_FILE="$(mktemp)"
START_TS="$(date +%s)"
END_TS="$((START_TS + DURATION_SECONDS))"

cleanup() {
  rm -f "$RESULTS_FILE"
}
trap cleanup EXIT

print_cluster_state() {
  if command -v kubectl >/dev/null 2>&1; then
    echo
    kubectl get hpa -n "$K8S_NAMESPACE" || true
    kubectl get pods -n "$K8S_NAMESPACE" -l app.kubernetes.io/name=worldcup-app || true
    kubectl top pods -n "$K8S_NAMESPACE" 2>/dev/null || true
  fi
}

echo "HPA CPU load test"
echo "target      : $TARGET_URL/api/compute"
echo "duration    : ${DURATION_SECONDS}s"
echo "concurrency : $CONCURRENCY"
echo

echo "Initial cluster state"
print_cluster_state
echo

for worker in $(seq 1 "$CONCURRENCY"); do
  (
    while [ "$(date +%s)" -lt "$END_TS" ]; do
      curl -sS -o /dev/null \
        --max-time "$REQUEST_TIMEOUT" \
        -w "%{http_code} %{time_total}\n" \
        "${TARGET_URL}/api/compute" >> "$RESULTS_FILE" 2>/dev/null || echo "000 0" >> "$RESULTS_FILE"
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
        printf("t+%ss | compute_requests=0\n", elapsed);
      } else {
        printf("t+%ss | compute_requests=%d | ok=%d | errors=%d | rps=%.2f | avg_latency=%.3fs\n",
          elapsed, total, ok, errors, total / elapsed, latency / total);
      }
    }
  ' "$RESULTS_FILE"
  print_cluster_state
done

wait

echo
echo "Load phase finished. Waiting ${COOLDOWN_SECONDS}s to observe HPA state..."
sleep "$COOLDOWN_SECONDS"
print_cluster_state

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
  }
' "$RESULTS_FILE"
