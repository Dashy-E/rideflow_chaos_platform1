from prometheus_client import Counter, Gauge


class ChaosMetrics:
    def __init__(self):
        self.runs_total = Counter(
            "chaos_experiment_runs_total", "experiment runs", ["experiment", "result"]
        )
        self.mttd = Gauge("chaos_mttd_seconds", "last MTTD", ["experiment"])
        self.mttr = Gauge("chaos_mttr_seconds", "last MTTR", ["experiment"])
        self.active_faults = Gauge("chaos_active_faults", "active faults", ["type", "target"])
        self.abort_total = Counter(
            "chaos_experiment_aborts_total", "aborted experiments", ["experiment", "reason"]
        )
