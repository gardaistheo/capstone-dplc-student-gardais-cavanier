/**
 * Property 2: Rejet des données de match invalides
 * Feature: capstone-cloud-resilience, Property 2: Rejet des données de match invalides
 *
 * **Validates: Requirements 4.2**
 *
 * For any corps JSON dont au moins un champ requis est manquant ou invalide
 * (nom d'équipe vide, score négatif, stage non reconnu, date au format non-ISO),
 * l'envoi d'un POST sur `/api/data` doit retourner HTTP 400 et la base de données
 * ne doit contenir aucun nouvel enregistrement.
 */

const fc = require('fast-check');
const request = require('supertest');

// Mock pg module before requiring the app
jest.mock('pg', () => {
  const mockQuery = jest.fn();
  const mockPool = {
    query: mockQuery,
    connect: jest.fn(),
    end: jest.fn(),
    on: jest.fn(),
  };
  return { Pool: jest.fn(() => mockPool) };
});

const { app, pool } = require('../main');

describe('Feature: capstone-cloud-resilience, Property 2: Rejet des données de match invalides', () => {
  beforeEach(() => {
    // Reset mock call counts before each test
    pool.query.mockClear();
  });

  // Valid base values for generating invalid combinations
  const validStages = ['Group Stage', 'Round of 16', 'Quarter-final', 'Semi-final', 'Final'];
  const validDate = '2026-06-15';
  const validTeamHome = 'France';
  const validTeamAway = 'Brazil';
  const validScoreHome = 2;
  const validScoreAway = 1;
  const validStage = 'Group Stage';

  // Generator for invalid match data - at least one field is invalid
  const invalidMatchDataArb = fc.oneof(
    // Case 1: Empty team_home
    fc.record({
      team_home: fc.constant(''),
      team_away: fc.string({ minLength: 1, maxLength: 50 }),
      score_home: fc.nat({ max: 20 }),
      score_away: fc.nat({ max: 20 }),
      stage: fc.constantFrom(...validStages),
      date: fc.constant(validDate),
    }),
    // Case 2: Empty team_away
    fc.record({
      team_home: fc.string({ minLength: 1, maxLength: 50 }),
      team_away: fc.constant(''),
      score_home: fc.nat({ max: 20 }),
      score_away: fc.nat({ max: 20 }),
      stage: fc.constantFrom(...validStages),
      date: fc.constant(validDate),
    }),
    // Case 3: Negative score_home
    fc.record({
      team_home: fc.string({ minLength: 1, maxLength: 50 }),
      team_away: fc.string({ minLength: 1, maxLength: 50 }),
      score_home: fc.integer({ min: -1000, max: -1 }),
      score_away: fc.nat({ max: 20 }),
      stage: fc.constantFrom(...validStages),
      date: fc.constant(validDate),
    }),
    // Case 4: Negative score_away
    fc.record({
      team_home: fc.string({ minLength: 1, maxLength: 50 }),
      team_away: fc.string({ minLength: 1, maxLength: 50 }),
      score_home: fc.nat({ max: 20 }),
      score_away: fc.integer({ min: -1000, max: -1 }),
      stage: fc.constantFrom(...validStages),
      date: fc.constant(validDate),
    }),
    // Case 5: Invalid stage
    fc.record({
      team_home: fc.string({ minLength: 1, maxLength: 50 }),
      team_away: fc.string({ minLength: 1, maxLength: 50 }),
      score_home: fc.nat({ max: 20 }),
      score_away: fc.nat({ max: 20 }),
      stage: fc.string({ minLength: 1, maxLength: 30 }).filter(
        (s) => !validStages.includes(s)
      ),
      date: fc.constant(validDate),
    }),
    // Case 6: Invalid date format (not YYYY-MM-DD)
    fc.record({
      team_home: fc.string({ minLength: 1, maxLength: 50 }),
      team_away: fc.string({ minLength: 1, maxLength: 50 }),
      score_home: fc.nat({ max: 20 }),
      score_away: fc.nat({ max: 20 }),
      stage: fc.constantFrom(...validStages),
      date: fc.oneof(
        // Various invalid date formats
        fc.constant('15/06/2026'),
        fc.constant('2026/06/15'),
        fc.constant('June 15, 2026'),
        fc.constant('not-a-date'),
        fc.constant(''),
        fc.constant('2026-13-45'),
        fc.string({ minLength: 1, maxLength: 20 }).filter(
          (s) => !/^\d{4}-\d{2}-\d{2}$/.test(s)
        ),
      ),
    }),
    // Case 7: Missing fields (partial data)
    fc.record({
      team_home: fc.string({ minLength: 1, maxLength: 50 }),
      // Missing team_away, scores, stage, date
    }),
    // Case 8: score_home is not an integer (float)
    fc.record({
      team_home: fc.string({ minLength: 1, maxLength: 50 }),
      team_away: fc.string({ minLength: 1, maxLength: 50 }),
      score_home: fc.double({ min: 0.1, max: 10, noInteger: true }),
      score_away: fc.nat({ max: 20 }),
      stage: fc.constantFrom(...validStages),
      date: fc.constant(validDate),
    })
  );

  it('should reject invalid match data with HTTP 400 and not call the database', async () => {
    await fc.assert(
      fc.asyncProperty(invalidMatchDataArb, async (invalidData) => {
        // Clear mock before each iteration
        pool.query.mockClear();

        const response = await request(app)
          .post('/api/data')
          .set('Content-Type', 'application/json')
          .send(invalidData);

        // 1. The response status must be 400
        expect(response.status).toBe(400);

        // 2. The response body must contain an error message
        expect(response.body).toHaveProperty('status', 'error');
        expect(response.body).toHaveProperty('message');
        expect(typeof response.body.message).toBe('string');
        expect(response.body.message.length).toBeGreaterThan(0);

        // 3. No database insertion should have been attempted
        // The pool.query should never have been called with an INSERT query
        const insertCalls = pool.query.mock.calls.filter(
          (call) => typeof call[0] === 'string' && call[0].toUpperCase().includes('INSERT')
        );
        expect(insertCalls).toHaveLength(0);
      }),
      { numRuns: 100, verbose: true }
    );
  });
});
