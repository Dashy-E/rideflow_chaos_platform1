from prometheus_client import Counter, Gauge

runs_total = Counter("security_attack_runs_total", "attack runs", ["attack", "verdict"])
findings_total = Counter("security_findings_total", "individual findings", ["attack", "check", "passed"])
vulnerabilities_open = Gauge("security_vulnerabilities_open", "findings currently marked vulnerable", ["attack", "check"])
