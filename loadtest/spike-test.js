// RideFlow spike test — ramps 50 -> 500 RPS over 2 minutes, then holds and
// ramps back down. Useful for demoing HPA scale-out live (doc §5.4 / §7.3,
// HPA behavior in the ride-service Deployment example).
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errors = new Rate('business_errors');
const BASE = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
  scenarios: {
    spike: {
      executor: 'ramping-arrival-rate',
      startRate: 50,
      timeUnit: '1s',
      preAllocatedVUs: 200,
      maxVUs: 1000,
      stages: [
        { target: 500, duration: '2m' },  // ramp 50 -> 500 RPS
        { target: 500, duration: '3m' },  // hold at peak to trigger HPA scale-out
        { target: 50, duration: '2m' },   // ramp back down to observe scale-in
      ],
    },
  },
  thresholds: {
    'http_req_duration{expected_response:true}': ['p(99)<2000'],
    'http_req_failed': ['rate<0.05'],
  },
};

export default function () {
  const r = Math.random();
  let res;
  if (r < 0.6) {
    res = http.get(`${BASE}/v1/drivers/nearby?lat=19.076&lng=72.877&radius=5`);
  } else if (r < 0.85) {
    res = http.post(
      `${BASE}/v1/rides`,
      JSON.stringify({
        userId: `k6-vu-${__VU}`,
        pickup: { lat: 19.076, lng: 72.877 },
        drop: { lat: 19.119, lng: 72.846 },
      }),
      { headers: { 'Content-Type': 'application/json' } }
    );
  } else {
    res = http.get(`${BASE}/v1/users/me`);
  }
  errors.add(res.status >= 500);
  check(res, { 'not a server error': (x) => x.status < 500 });
  sleep(0.05);
}
