"""Minimal per-dependency circuit breaker: opens after 5 consecutive failures,
half-opens after 15s to probe, closes again on a successful probe."""
import time
from enum import IntEnum


class State(IntEnum):
    CLOSED = 0
    HALF_OPEN = 1
    OPEN = 2


class CircuitBreaker:
    def __init__(self, failure_threshold: int = 5, reset_after_s: float = 15.0):
        self.failure_threshold = failure_threshold
        self.reset_after_s = reset_after_s
        self.failures = 0
        self.state = State.CLOSED
        self.opened_at: float | None = None

    def allow(self) -> bool:
        if self.state == State.OPEN:
            if self.opened_at and time.time() - self.opened_at >= self.reset_after_s:
                self.state = State.HALF_OPEN
                return True
            return False
        return True

    def record_success(self):
        self.failures = 0
        self.state = State.CLOSED
        self.opened_at = None

    def record_failure(self):
        self.failures += 1
        if self.state == State.HALF_OPEN or self.failures >= self.failure_threshold:
            self.state = State.OPEN
            self.opened_at = time.time()
