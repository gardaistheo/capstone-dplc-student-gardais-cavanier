/**
 * Property-Based Test: Round-trip de vote
 *
 * Feature: capstone-cloud-resilience, Property 5: Round-trip de vote
 * Validates: Requirements 16.1
 *
 * For any valid team_id referencing an existing team in the teams table (1-48),
 * POST /api/vote with {"team_id": id} must return HTTP 201 with a vote id,
 * and the vote count for that team in /api/votes/results must have increased by exactly 1.
 */

const fc = require('fast-check');
const request = require('supertest');

// Mock pg before requiring the app
jest.mock('pg', () => {
  const mockQuery = jest.fn();
  const mockPool = { query: mockQuery };
  return { Pool: jest.fn(() => mockPool) };
});

const { app, pool } = require('../main');

describe('Feature: capstone-cloud-resilience, Property 5: Round-trip de vote', () => {
  // Track votes per team for verifying the round-trip
  let voteStore;
  let nextVoteId;

  beforeEach(() => {
    voteStore = {};
    nextVoteId = 1;
    pool.query.mockReset();
  });

  afterAll(() => {
    jest.restoreAllMocks();
  });

  it('should return HTTP 201 with a vote id and increase the vote count by exactly 1 for any valid team_id', async () => {
    await fc.assert(
      fc.asyncProperty(
        fc.integer({ min: 1, max: 48 }),
        async (teamId) => {
          // Reset vote store for this iteration to cleanly test the +1 property
          const votesBeforeForTeam = voteStore[teamId] || 0;

          // Mock pool.query to simulate DB behavior
          pool.query.mockImplementation((sql, params) => {
            // SELECT id FROM teams WHERE id = $1 -> team exists for ids 1-48
            if (sql.includes('SELECT id FROM teams WHERE id')) {
              const id = params[0];
              if (id >= 1 && id <= 48) {
                return Promise.resolve({ rows: [{ id }] });
              }
              return Promise.resolve({ rows: [] });
            }

            // INSERT INTO votes (team_id) VALUES ($1) RETURNING id
            if (sql.includes('INSERT INTO votes')) {
              const insertedTeamId = params[0];
              voteStore[insertedTeamId] = (voteStore[insertedTeamId] || 0) + 1;
              const voteId = nextVoteId++;
              return Promise.resolve({ rows: [{ id: voteId }] });
            }

            // GET /api/votes/results query
            if (sql.includes('SELECT') && sql.includes('votes') && sql.includes('teams')) {
              const rows = Object.entries(voteStore)
                .filter(([, count]) => count > 0)
                .map(([tId, count]) => ({
                  team_id: parseInt(tId, 10),
                  team_name: `Team ${tId}`,
                  votes: String(count),
                }));
              return Promise.resolve({ rows });
            }

            return Promise.resolve({ rows: [] });
          });

          // Step 1: POST /api/vote with valid team_id
          const voteRes = await request(app)
            .post('/api/vote')
            .set('Content-Type', 'application/json')
            .send({ team_id: teamId });

          // Property assertion 1: Response status is 201
          expect(voteRes.status).toBe(201);

          // Property assertion 2: Response body contains an id field
          expect(voteRes.body).toHaveProperty('id');
          expect(typeof voteRes.body.id).toBe('number');

          // Step 2: GET /api/votes/results to verify the count increased
          const resultsRes = await request(app)
            .get('/api/votes/results');

          expect(resultsRes.status).toBe(200);

          // Property assertion 3: The vote count for this team increased by exactly 1
          const teamResult = resultsRes.body.find(r => r.team_id === teamId);
          expect(teamResult).toBeDefined();

          const votesAfterForTeam = teamResult.votes;
          expect(votesAfterForTeam).toBe(votesBeforeForTeam + 1);
        }
      ),
      { numRuns: 100 }
    );
  });
});
