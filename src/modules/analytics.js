"use strict";
module.exports = (db, now = new Date()) => {
  const today = new Date(now.getTime() + 8 * 3600000)
      .toISOString()
      .slice(0, 10),
    day = new Date(`${today}T00:00:00Z`);
  const offset = (n) =>
    new Date(day.getTime() + n * 86400000).toISOString().slice(0, 10);
  const repository = require("../db/analytics.repository")(db);
  // Manila has no daylight saving: local midnight is 16:00 UTC on the prior day.
  const utcMidnight = (date) =>
    new Date(Date.parse(`${date}T00:00:00Z`) - 8 * 3600000).toISOString();
  const end = utcMidnight(offset(1));
  const total = (start) => repository.total(utcMidnight(start), end);
  const chart = repository.chart(utcMidnight(offset(-6)), end);
  const dates = Array.from({ length: 7 }, (_, i) => offset(i - 6));
  return {
    kpis: {
      today: total(today),
      week: total(offset(-day.getUTCDay())),
      month: total(today.slice(0, 7) + "-01"),
      year: total(today.slice(0, 4) + "-01-01"),
    },
    popularItems: repository.popular(),
    chartData: {
      labels: dates,
      data: dates.map(
        (date) => chart.find((r) => r.sale_date === date)?.total || 0,
      ),
    },
  };
};
