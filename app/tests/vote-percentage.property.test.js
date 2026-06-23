/**
 * Property 7: Cohérence des pourcentages de résultats de votes
 * Feature: capstone-cloud-resilience, Property 7: Cohérence des pourcentages de résultats de votes
 *
 * Validates: Requirements 16.4
 *
 * For any ensemble de votes insérés dans la table votes (au moins un vote),
 * la somme de tous les champs percentage retournés par GET /api/votes/results
 * doit être égale à 100 (à l'arrondi près ±1), et pour chaque équipe le champ
 * votes doit correspondre exactement au nombre de lignes dans la table votes
 * pour cette équipe.
 */

const request = require('supertest');
const fc = require('fast-check');

// Team names mapping (simulating the 48 teams)
const TEAM_NAMES = {};
for (let i = 1; i <= 48; i++) {
  TEAM_NAMES[i] = `Team ${i}`;
}

// Mock pg module before requiring the app
jest.mock('pg', () => {
  const mockPool = {
    query: jest.fn(),
    end: jest.fn(),
    on: jest.fn(),
  };
  return { Pool: jest.fn(() => mockPool) };
});

// Mock prom-client to avoid side effects
jest.mock('prom-client', () => ({
  collectDefaultMetrics: jest.fn(),
  Counter: jest.fn().mockImplementation(() => ({ inc: jest.fn() })),
  Histogram: jest.fn().mockImplementation(() => ({
    startTimer: jest.fn(() => jest.fn()),
  })),
  register: { metrics: jest.fn().mockResolvedValue('') },
}));

// We need to prevent app.listen from binding a port.
// Override Express prototype listen before requiring main.js
const express = require('express');
const originalListen = express.application.listen;
express.application.listen = function () {
  // no-op: don't actually bind to any port
  const cb = arguments[arguments.length - 1];
  if (typeof cb === 'function') cb();
  return { close: jest.fn(), address: () => ({ port: 0 }) };
};

const { app, pool } = require('../main');

// Restore after require
express.application.listen = originalListen;

describe('Feature: capstone-cloud-resilience, Property 7: Cohérence des pourcentages de résultats de votes', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should return percentages summing to 100 (±1) and correct vote counts for any set of votes', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.array(fc.integer({ min: 1, max: 48 }), { minLength: 1, maxLength: 200 }),
        async (votes) => {
          // Count votes per team
          const voteCounts = {};
          for (const teamId of votes) {
            voteCounts[teamId] = (voteCounts[teamId] || 0) + 1;
          }

          // Build mock DB result: what PostgreSQL would return with COUNT grouped by team
          const mockRows = Object.entries(voteCounts)
            .map(([teamId, count]) => ({
              team_id: parseInt(teamId, 10),
              team_name: TEAM_NAMES[parseInt(teamId, 10)],
              votes: String(count), // PostgreSQL COUNT returns string
            }))
            .sort((a, b) => parseInt(b.votes, 10) - parseInt(a.votes, 10));

          // Mock pool.query for the results endpoint
          pool.query.mockResolvedValueOnce({ rows: mockRows });

          const response = await request(app).get('/api/votes/results');

          // 1. GET /api/votes/results returns HTTP 200
          expect(response.status).toBe(200);

          const results = response.body;

          // 2. The sum of all percentage fields equals 100 (±1 tolerance for rounding)
          const totalPercentage = results.reduce((sum, r) => sum + r.percentage, 0);
          expect(totalPercentage).toBeGreaterThanOrEqual(99);
          expect(totalPercentage).toBeLessThanOrEqual(101);

          // 3. For each team in the results, votes equals the actual count
          for (const result of results) {
            const expectedCount = voteCounts[result.team_id];
            expect(result.votes).toBe(expectedCount);
          }
        }
      ),
      { numRuns: 100 }
    );
  });
});
