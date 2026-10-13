// RideFlow steady-state load profile — doc Appendix B, adjusted so BASE_URL
// defaults to http://localhost:8080 (api-gateway, per docs/api/contracts.md)
// when not supplied via -e BASE_URL=...
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Rate } from 'k6/metrics';

const errors = new Rate('business_errors');
const BASE = __ENV.BASE_URL || 'http://localhost:8080';

export const options = {
  scenarios: {
    steady: {
      executor: 'constant-arrival-rate',
      rate: 200,
      timeUnit: '1s',
      duration: '30m',
      preAllocatedVUs: 100,
      maxVUs: 400,
    },
  },
  thresholds: {
    'http_req_duration{expected_response:true}': ['p(99)<1500'],
    'http_req_failed': ['rate<0.01'],
  },
};

export default function () {
  const r = Math.random();
  let res;
  if (r < 0.6) {
    // 60% nearby-drivers
    res = http.get(`${BASE}/v1/drivers/nearby?lat=19.076&lng=72.877&radius=5`);
  } else if (r < 0.85) {
    // 25% create-ride
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
    // 15% status (profile lookup)
    res = http.get(`${BASE}/v1/users/me`);
  }
  errors.add(res.status >= 500);
  check(res, { 'not a server error': (x) => x.status < 500 });
  sleep(0.1);
}
