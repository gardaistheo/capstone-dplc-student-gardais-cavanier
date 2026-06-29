-- Mission 3 - Job planifie de materialisation du classement.
-- Lit les tables teams/matches et ecrit un snapshot exploitable pour la demo.

BEGIN;

CREATE TABLE IF NOT EXISTS group_standings_snapshots (
    snapshot_id BIGSERIAL PRIMARY KEY,
    generated_at TIMESTAMPTZ NOT NULL,
    group_letter CHAR(1) NOT NULL,
    rank INTEGER NOT NULL,
    team_id INTEGER NOT NULL REFERENCES teams(id),
    team_name VARCHAR(100) NOT NULL,
    played INTEGER NOT NULL,
    won INTEGER NOT NULL,
    drawn INTEGER NOT NULL,
    lost INTEGER NOT NULL,
    goals_for INTEGER NOT NULL,
    goals_against INTEGER NOT NULL,
    goal_difference INTEGER NOT NULL,
    points INTEGER NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_group_standings_snapshots_generated_at
    ON group_standings_snapshots (generated_at DESC);

CREATE INDEX IF NOT EXISTS idx_group_standings_snapshots_group_rank
    ON group_standings_snapshots (generated_at DESC, group_letter, rank);

WITH snapshot_clock AS (
    SELECT NOW() AS generated_at
),
match_results AS (
    SELECT
        team_home_id AS team_id,
        score_home AS goals_for,
        score_away AS goals_against,
        CASE WHEN score_home > score_away THEN 1 ELSE 0 END AS won,
        CASE WHEN score_home = score_away THEN 1 ELSE 0 END AS drawn,
        CASE WHEN score_home < score_away THEN 1 ELSE 0 END AS lost,
        CASE
            WHEN score_home > score_away THEN 3
            WHEN score_home = score_away THEN 1
            ELSE 0
        END AS points
    FROM matches
    WHERE stage = 'Group Stage'

    UNION ALL

    SELECT
        team_away_id AS team_id,
        score_away AS goals_for,
        score_home AS goals_against,
        CASE WHEN score_away > score_home THEN 1 ELSE 0 END AS won,
        CASE WHEN score_away = score_home THEN 1 ELSE 0 END AS drawn,
        CASE WHEN score_away < score_home THEN 1 ELSE 0 END AS lost,
        CASE
            WHEN score_away > score_home THEN 3
            WHEN score_away = score_home THEN 1
            ELSE 0
        END AS points
    FROM matches
    WHERE stage = 'Group Stage'
),
team_stats AS (
    SELECT
        t.id AS team_id,
        t.name AS team_name,
        t.group_letter,
        COUNT(mr.team_id)::INTEGER AS played,
        COALESCE(SUM(mr.won), 0)::INTEGER AS won,
        COALESCE(SUM(mr.drawn), 0)::INTEGER AS drawn,
        COALESCE(SUM(mr.lost), 0)::INTEGER AS lost,
        COALESCE(SUM(mr.goals_for), 0)::INTEGER AS goals_for,
        COALESCE(SUM(mr.goals_against), 0)::INTEGER AS goals_against,
        COALESCE(SUM(mr.goals_for - mr.goals_against), 0)::INTEGER AS goal_difference,
        COALESCE(SUM(mr.points), 0)::INTEGER AS points
    FROM teams t
    LEFT JOIN match_results mr ON mr.team_id = t.id
    GROUP BY t.id, t.name, t.group_letter
),
ranked_teams AS (
    SELECT
        sc.generated_at,
        ts.*,
        ROW_NUMBER() OVER (
            PARTITION BY ts.group_letter
            ORDER BY ts.points DESC, ts.goal_difference DESC, ts.goals_for DESC, ts.team_name ASC
        )::INTEGER AS rank
    FROM team_stats ts
    CROSS JOIN snapshot_clock sc
)
INSERT INTO group_standings_snapshots (
    generated_at,
    group_letter,
    rank,
    team_id,
    team_name,
    played,
    won,
    drawn,
    lost,
    goals_for,
    goals_against,
    goal_difference,
    points
)
SELECT
    generated_at,
    group_letter,
    rank,
    team_id,
    team_name,
    played,
    won,
    drawn,
    lost,
    goals_for,
    goals_against,
    goal_difference,
    points
FROM ranked_teams
ORDER BY group_letter, rank;

COMMIT;
