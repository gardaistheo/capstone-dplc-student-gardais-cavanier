/**
 * Property 6: Rejet des votes invalides
 * Feature: capstone-cloud-resilience, Property 6: Rejet des votes invalides
 *
 * **Validates: Requirements 16.2**
 *
 * For any valeur team_id qui est soit manquante, soit non-entière, soit
 * référençant un identifiant inexistant dans la table teams (entier négatif,
 * zéro, supérieur au nombre d'équipes, chaîne, null), l'envoi d'un POST sur
 * /api/vote doit retourner HTTP 400 et la table votes ne doit contenir aucun
 * nouvel enregistrement.
 */

const fc = require('fast-check');
const request = require('supertest');

// Mock the pg module before requiring the app
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

// Prevent the server from actually listening on a port during tests
jest.mock('express', () => {
  const actualExpress = jest.requireActual('express');
  const originalFunc = actualExpress;
  const mockExpress = (...args) => {
    const app = originalFunc(...args);
    app.listen = jest.fn((port, cb) => {
      if (cb) cb();
      return { close: jest.fn() };
    });
    return app;
  };
  Object.assign(mockExpress, actualExpress);
  mockExpress.json = actualExpress.json;
  return mockExpress;
});

const { app, pool } = require('../main.js');

describe('Feature: capstone-cloud-resilience, Property 6: Rejet des votes invalides', () => {
  beforeEach(() => {
    jest.clearAllMocks();
  });

  it('should reject any invalid team_id with HTTP 400 and no vote inserted', async () => {
    // Mock: SELECT id FROM teams WHERE id = $1 returns empty for invalid ids
    pool.query.mockImplementation((query, params) => {
      if (typeof query === 'string' && query.includes('SELECT id FROM teams WHERE id')) {
        // Always return empty rows for invalid team_ids
        return Promise.resolve({ rows: [] });
      }
      if (typeof query === 'string' && query.includes('INSERT INTO votes')) {
        // This should never be called for invalid votes
        return Promise.resolve({ rows: [{ id: 999 }] });
      }
      return Promise.resolve({ rows: [] });
    });

    await fc.assert(
      fc.asyncProperty(
        fc.oneof(
          fc.integer({ max: 0 }),        // Negative integers and zero
          fc.integer({ min: 49 }),        // Too large (>48 teams)
          fc.string(),                    // Non-integer strings
          fc.constant(null)              // Null value
        ),
        async (invalidTeamId) => {
          pool.query.mockClear();

          // Re-setup mock after clear
          pool.query.mockImplementation((query, params) => {
            if (typeof query === 'string' && query.includes('SELECT id FROM teams WHERE id')) {
              return Promise.resolve({ rows: [] });
            }
            if (typeof query === 'string' && query.includes('INSERT INTO votes')) {
              return Promise.resolve({ rows: [{ id: 999 }] });
            }
            return Promise.resolve({ rows: [] });
          });

          const body = invalidTeamId === null
            ? { team_id: null }
            : { team_id: invalidTeamId };

          const response = await request(app)
            .post('/api/vote')
            .send(body)
            .set('Content-Type', 'application/json');

          // 1. POST /api/vote with invalid team_id returns HTTP 400
          expect(response.status).toBe(400);

          // 2. The response body contains an error message
          expect(response.body).toHaveProperty('status', 'error');
          expect(response.body).toHaveProperty('message');
          expect(response.body.message.length).toBeGreaterThan(0);

          // 3. No vote was inserted in the database
          const insertCalls = pool.query.mock.calls.filter(
            (call) => typeof call[0] === 'string' && call[0].includes('INSERT INTO votes')
          );
          expect(insertCalls).toHaveLength(0);
        }
      ),
      { numRuns: 100 }
    );
  });

  it('should reject a request with missing team_id with HTTP 400', async () => {
    const response = await request(app)
      .post('/api/vote')
      .send({})
      .set('Content-Type', 'application/json');

    expect(response.status).toBe(400);
    expect(response.body).toHaveProperty('status', 'error');
    expect(response.body).toHaveProperty('message');

    // Verify no INSERT was called
    const insertCalls = pool.query.mock.calls.filter(
      (call) => typeof call[0] === 'string' && call[0].includes('INSERT INTO votes')
    );
    expect(insertCalls).toHaveLength(0);
  });
});
