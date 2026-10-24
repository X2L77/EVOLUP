// Best-effort protection against excessive calls.
//
// Counters live in the memory of one function instance: they reset on a cold
// start and are not shared between instances, so they slow down bursts but
// are NOT a reliable per-user quota. A reliable quota needs persistent
// storage (e.g. a `coach_usage` table written by this function), which is
// left for a later, separately approved migration.

export type RateDecision =
  | { allowed: true }
  | { allowed: false; retryAfterSeconds: number };

export interface RateLimiter {
  tryAcquire(userId: string, now: number): RateDecision;
  /** Frees the in-flight slot taken by a successful [tryAcquire]. */
  release(userId: string): void;
}

export interface RateLimits {
  perMinute: number;
  perHour: number;
  /** Requests of the same user processed at the same time. */
  concurrent: number;
}

export const DEFAULT_RATE_LIMITS: RateLimits = {
  perMinute: 5,
  perHour: 30,
  concurrent: 1,
};

const MINUTE = 60_000;
const HOUR = 60 * MINUTE;
const MAX_TRACKED_USERS = 10_000;

type UserState = { calls: number[]; inFlight: number };

export class InMemoryRateLimiter implements RateLimiter {
  #users = new Map<string, UserState>();

  constructor(private readonly limits: RateLimits = DEFAULT_RATE_LIMITS) {}

  tryAcquire(userId: string, now: number): RateDecision {
    const state = this.#users.get(userId) ?? { calls: [], inFlight: 0 };
    state.calls = state.calls.filter((time) => now - time < HOUR);
    if (state.inFlight >= this.limits.concurrent) {
      return { allowed: false, retryAfterSeconds: 5 };
    }
    const lastMinute = state.calls.filter((time) => now - time < MINUTE);
    if (lastMinute.length >= this.limits.perMinute) {
      return {
        allowed: false,
        retryAfterSeconds: secondsUntil(lastMinute[0] + MINUTE, now),
      };
    }
    if (state.calls.length >= this.limits.perHour) {
      return {
        allowed: false,
        retryAfterSeconds: secondsUntil(state.calls[0] + HOUR, now),
      };
    }
    state.calls.push(now);
    state.inFlight += 1;
    this.#users.delete(userId);
    this.#users.set(userId, state);
    if (this.#users.size > MAX_TRACKED_USERS) {
      const oldest = this.#users.keys().next().value;
      if (oldest !== undefined) this.#users.delete(oldest);
    }
    return { allowed: true };
  }

  release(userId: string): void {
    const state = this.#users.get(userId);
    if (state && state.inFlight > 0) state.inFlight -= 1;
  }
}

function secondsUntil(time: number, now: number): number {
  return Math.max(1, Math.ceil((time - now) / 1000));
}
