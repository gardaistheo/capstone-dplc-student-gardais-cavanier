// ============================================================
// FIFA World Cup 2026 - Frontend Application
// ============================================================

(function () {
  'use strict';

  // Navigation
  const navButtons = document.querySelectorAll('.nav-btn');
  const sections = document.querySelectorAll('.section');

  navButtons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const target = btn.dataset.section;
      navButtons.forEach((b) => b.classList.remove('active'));
      sections.forEach((s) => s.classList.remove('active'));
      btn.classList.add('active');
      document.getElementById(target).classList.add('active');

      // Load data for the section
      loadSection(target);
    });
  });

  // Load section data
  function loadSection(section) {
    switch (section) {
      case 'groups':
        loadGroups();
        break;
      case 'standings':
        loadStandings();
        break;
      case 'matches':
        loadMatches();
        break;
      case 'vote':
        loadVoteTeams();
        break;
      case 'results':
        loadResults();
        break;
    }
  }

  // ============================================================
  // Groups
  // ============================================================

  async function loadGroups() {
    const container = document.getElementById('groups-container');
    container.innerHTML = '<div class="loading">Loading groups</div>';

    try {
      const res = await fetch('/api/groups');
      const groups = await res.json();

      container.innerHTML = '';
      const sortedKeys = Object.keys(groups).sort();

      for (const letter of sortedKeys) {
        const card = document.createElement('div');
        card.className = 'group-card';
        card.innerHTML = `
          <h3>Group ${letter}</h3>
          <ul>
            ${groups[letter]
              .map(
                (team) => `
              <li>
                <span class="country-code">${team.country_code}</span>
                <span>${team.name}</span>
              </li>
            `
              )
              .join('')}
          </ul>
        `;
        container.appendChild(card);
      }
    } catch (err) {
      container.innerHTML = '<p class="no-results">Failed to load groups.</p>';
    }
  }

  // ============================================================
  // Standings
  // ============================================================

  async function loadStandings() {
    const container = document.getElementById('standings-container');
    container.innerHTML = '<div class="loading">Loading standings</div>';

    try {
      const res = await fetch('/api/standings');
      const groups = await res.json();

      container.innerHTML = '';
      const sortedKeys = Object.keys(groups).sort();

      for (const letter of sortedKeys) {
        const card = document.createElement('div');
        card.className = 'standings-card';
        card.innerHTML = `
          <h3>Group ${letter}</h3>
          <table class="standings-table">
            <thead>
              <tr>
                <th>Team</th>
                <th>P</th>
                <th>W</th>
                <th>D</th>
                <th>L</th>
                <th>GF</th>
                <th>GA</th>
                <th>GD</th>
                <th>Pts</th>
              </tr>
            </thead>
            <tbody>
              ${groups[letter]
                .map(
                  (team) => `
                <tr>
                  <td>${team.name}</td>
                  <td>${team.played}</td>
                  <td>${team.won}</td>
                  <td>${team.drawn}</td>
                  <td>${team.lost}</td>
                  <td>${team.goals_for}</td>
                  <td>${team.goals_against}</td>
                  <td>${team.goal_difference > 0 ? '+' : ''}${team.goal_difference}</td>
                  <td class="points">${team.points}</td>
                </tr>
              `
                )
                .join('')}
            </tbody>
          </table>
        `;
        container.appendChild(card);
      }
    } catch (err) {
      container.innerHTML = '<p class="no-results">Failed to load standings.</p>';
    }
  }

  // ============================================================
  // Matches
  // ============================================================

  async function loadMatches() {
    const container = document.getElementById('matches-container');
    container.innerHTML = '<div class="loading">Loading matches</div>';

    try {
      const res = await fetch('/api/matches');
      const matches = await res.json();

      if (matches.length === 0) {
        container.innerHTML = '<p class="no-results">No matches played yet.</p>';
        return;
      }

      container.innerHTML = '';

      // Group matches by date
      const byDate = {};
      for (const match of matches) {
        const date = match.match_date.split('T')[0];
        if (!byDate[date]) byDate[date] = [];
        byDate[date].push(match);
      }

      for (const date of Object.keys(byDate).sort()) {
        const dateHeader = document.createElement('h3');
        dateHeader.style.margin = '1.5rem 0 0.75rem';
        dateHeader.style.color = '#6c757d';
        dateHeader.style.fontSize = '0.9rem';
        dateHeader.style.textTransform = 'uppercase';
        dateHeader.textContent = formatDate(date);
        container.appendChild(dateHeader);

        for (const match of byDate[date]) {
          const card = document.createElement('div');
          card.className = 'match-card';
          card.innerHTML = `
            <div class="team-home">
              <div>${match.team_home}</div>
              <div class="match-meta">${match.stage}</div>
            </div>
            <div class="match-score">${match.score_home} - ${match.score_away}</div>
            <div class="team-away">
              <div>${match.team_away}</div>
            </div>
          `;
          container.appendChild(card);
        }
      }
    } catch (err) {
      container.innerHTML = '<p class="no-results">Failed to load matches.</p>';
    }
  }

  // ============================================================
  // Vote
  // ============================================================

  async function loadVoteTeams() {
    const container = document.getElementById('vote-container');
    container.innerHTML = '<div class="loading">Loading teams</div>';

    try {
      const res = await fetch('/api/teams');
      const teams = await res.json();

      container.innerHTML = '';

      for (const team of teams) {
        const btn = document.createElement('button');
        btn.className = 'vote-btn';
        btn.textContent = `${team.country_code} ${team.name}`;
        btn.setAttribute('aria-label', `Vote for ${team.name}`);
        btn.addEventListener('click', () => castVote(team.id, team.name, btn));
        container.appendChild(btn);
      }
    } catch (err) {
      container.innerHTML = '<p class="no-results">Failed to load teams.</p>';
    }
  }

  async function castVote(teamId, teamName, btnElement) {
    const feedback = document.getElementById('vote-feedback');

    try {
      const res = await fetch('/api/vote', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ team_id: teamId }),
      });

      const data = await res.json();

      if (res.ok) {
        feedback.className = 'feedback success';
        feedback.textContent = `Vote registered for ${teamName}!`;
        feedback.classList.remove('hidden');
        btnElement.classList.add('voted');
      } else {
        feedback.className = 'feedback error';
        feedback.textContent = data.message || 'Failed to register vote.';
        feedback.classList.remove('hidden');
      }

      // Auto-hide feedback after 3s
      setTimeout(() => feedback.classList.add('hidden'), 3000);
    } catch (err) {
      feedback.className = 'feedback error';
      feedback.textContent = 'Network error. Please try again.';
      feedback.classList.remove('hidden');
    }
  }

  // ============================================================
  // Results
  // ============================================================

  async function loadResults() {
    const container = document.getElementById('results-container');
    container.innerHTML = '<div class="loading">Loading results</div>';

    try {
      const res = await fetch('/api/votes/results');
      const results = await res.json();

      if (results.length === 0) {
        container.innerHTML = '<p class="no-results">No votes cast yet. Be the first to vote!</p>';
        return;
      }

      container.innerHTML = '';
      const maxPercentage = results[0].percentage || 1;

      for (const result of results) {
        const barWidth = (result.percentage / maxPercentage) * 100;
        const bar = document.createElement('div');
        bar.className = 'result-bar';
        bar.innerHTML = `
          <div class="bar-fill" style="width: ${barWidth}%"></div>
          <span class="team-name">${result.team_name}</span>
          <span class="vote-count">${result.votes} vote${result.votes !== 1 ? 's' : ''}</span>
          <span class="percentage">${result.percentage}%</span>
        `;
        container.appendChild(bar);
      }
    } catch (err) {
      container.innerHTML = '<p class="no-results">Failed to load results.</p>';
    }
  }

  // ============================================================
  // Helpers
  // ============================================================

  function formatDate(dateStr) {
    const date = new Date(dateStr + 'T00:00:00Z');
    return date.toLocaleDateString('en-US', {
      weekday: 'long',
      year: 'numeric',
      month: 'long',
      day: 'numeric',
      timeZone: 'UTC',
    });
  }

  // Initial load
  loadGroups();
})();
