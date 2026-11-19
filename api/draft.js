
export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = process.env.GROQ_API_KEY;

  if (!apiKey) {
    return res.status(500).json({ error: "GROQ_API_KEY is missing." });
  }

  const draft = req.body?.draft;

  if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
    return res.status(400).json({ error: "A valid draft object is required." });
  }

  const BASE = "https://mlbbdex.com/api/v1";

  const rankAliases = {
    epic: "epic",
    legend: "legend",
    mythic: "mythic",
    honor: "honor",
    "mythical honor": "honor",
    glory: "glory",
    "mythical glory": "glory"
  };

  const requestedRank = String(draft.rank || "glory").toLowerCase();
  const rank = rankAliases[requestedRank] || "glory";
  const lane = String(draft.lane || draft.requestedLane || "Gold");

  const normalize = value =>
    String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");

  async function getJSON(url) {
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(10000)
    });

    if (!response.ok) {
      throw new Error(`MLBBDex request failed: ${response.status}`);
    }

    return response.json();
  }

  const getName = item =>
    typeof item === "string" ? item : item?.name || item?.hero || "";

  const getField = (hero, first, second) =>
    hero?.[first] ?? hero?.[second] ?? [];

  function compactCounterList(list, heroes) {
    if (!Array.isArray(list)) return [];

    return list.slice(0, 5).map(item => ({
      hero:
        heroes.find(h => h.slug === item.slug)?.name ||
        item.name ||
        item.slug ||
        "Unknown",
      advantage: item.advantage ?? null
    }));
  }

  try {
    // Load hero catalogue and ranked statistics.
    const [heroResult, rankingResult] = await Promise.all([
      getJSON(`${BASE}/heroes`),
      getJSON(`${BASE}/rankings`)
    ]);

    const heroes = Array.isArray(heroResult.data)
      ? heroResult.data
      : [];

    const rankings = Array.isArray(rankingResult.data?.heroes)
      ? rankingResult.data.heroes
      : Array.isArray(rankingResult.data)
        ? rankingResult.data
        : [];

    if (!heroes.length) throw new Error("Hero catalogue is empty.");
    if (!rankings.length) throw new Error("Rankings unavailable.");

    const heroMap = new Map(
      heroes.map(hero => [normalize(hero.name), hero])
    );

    const rankingMap = new Map(
      rankings.map(hero => [hero.slug, hero])
    );

    const allied = Array.isArray(draft.allied)
      ? draft.allied.map(getName).filter(Boolean)
      : [];

    const enemy = Array.isArray(draft.enemy)
      ? draft.enemy.map(getName).filter(Boolean)
      : [];

    const pickedNames = [
      ...new Set([...allied, ...enemy])
    ];

    // Fetch actual profiles and matchup data for picked heroes only.
    const profileResults = await Promise.allSettled(
      pickedNames.slice(0, 10).map(async name => {
        const hero = heroMap.get(normalize(name));
        if (!hero?.slug) return null;

        const [profileResult, counterResult] = await Promise.allSettled([
          getJSON(`${BASE}/heroes/${encodeURIComponent(hero.slug)}`),
          getJSON(`${BASE}/heroes/${encodeURIComponent(hero.slug)}/counters`)
        ]);

        const profile =
          profileResult.status === "fulfilled"
            ? profileResult.value.data
            : null;

        const counterData =
          counterResult.status === "fulfilled"
            ? counterResult.value.data?.[rank]
            : null;

        return {
          name: hero.name,
          roles: getField(hero, "roles", "role"),
          lanes: getField(hero, "lanes", "lane"),

          // Only actual profile data; no generated ability descriptions.
          skills: profile?.skills ?? profile?.skill ?? null,

          counters: counterData
            ? {
                baselineWinRate: counterData.winRate ?? null,
                strongAgainst: compactCounterList(
                  counterData.strong,
                  heroes
                ),
                weakAgainst: compactCounterList(
                  counterData.weak,
                  heroes
                )
              }
            : null
        };
      })
    );

    const pickedDetails = profileResults
      .filter(result => result.status === "fulfilled")
      .map(result => result.value)
      .filter(Boolean);

    // Every hero remains eligible, except Wanwan.
    const catalogue = heroes
      .filter(hero => normalize(hero.name) !== "wanwan")
      .map(hero => {
        const stats = rankingMap.get(hero.slug);

        return {
          name: hero.name,
          roles: getField(hero, "roles", "role"),
          lanes: getField(hero, "lanes", "lane"),
          tier: stats?.tier ?? null,
          winRate: stats?.winRate ?? null,
          pickRate: stats?.pickRate ?? null,
          banRate: stats?.banRate ?? null
        };
      });

    const mlbbData = {
      source: "MLBBDex",
      sourceURL: "https://mlbbdex.com/en",
      rankingMeasuredAt: rankingResult.data?.measuredAt ?? null,
      rank,
      requestedLane: lane,
      allied,
      enemy,
      pickedHeroes: pickedDetails,
      availableHeroes: catalogue
    };

    const instructions = `
You are a careful professional Mobile Legends: Bang Bang draft coach.

IMPORTANT ACCURACY RULES:

1. Treat the supplied MLBBDex data as your factual source.
2. NEVER invent hero abilities, shields, stuns, damage,
   healing, mobility, immunity or crowd control.
3. Only describe a hero's specific abilities if their
   actual skill descriptions are included in the data.
4. For heroes without supplied skill descriptions,
   discuss only their supplied roles, lanes and statistics.
5. NEVER invent win rates, pick rates, ban rates or tiers.
6. NEVER invent percentage lane advantages or matchup gaps.
7. A statistical counter is evidence, not proof of a guaranteed win.
8. If matchup information is missing, clearly say so.
9. Never claim a synergy or counter is statistically proven
   unless the supplied data supports it.
10. Never recommend Wanwan.
11. Recommend only heroes in availableHeroes.
12. Do not confuse ranked statistics with MPL or pro statistics.
    No professional tournament statistics are supplied here.

PLAYER PREFERENCES:

- Consider all available heroes.
- Prioritize ${lane} lane.
- The player especially likes Fighter Gold Lane.
- Consider legitimate flexible picks such as Mage Gold,
  Fighter Gold, Tank EXP and Fighter EXP.
- Do not recommend an unusual lane without explaining
  the risks and whether the supplied lane data supports it.

DRAFT ANALYSIS:

Evaluate:
- Allied and enemy composition.
- Available lane options.
- Supplied matchup counters.
- Team damage balance.
- Frontline and crowd control, only when supported by facts.
- Early, mid and late game considerations, without inventing
  specific abilities or statistics.
- The safest and strongest practical remaining pick.

RESPONSE FORMAT:

1. BEST PICK
2. TWO ALTERNATIVES
3. LANE MATCHUP
4. VERIFIED COUNTERS AND SYNERGIES
5. TEAM COMPOSITION
6. WARNINGS

For each recommendation, explain what is supported by data
and what is your strategic judgment.

If data is insufficient, say so instead of guessing.
Be concise, practical and decisive.
`;

    const aiResponse = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${apiKey}`
        },
        body: JSON.stringify({
          model: process.env.GROQ_MODEL || "openai/gpt-oss-120b",
          messages: [
            {
              role: "system",
              content: instructions
            },
            {
              role: "user",
              content:
                "ACTUAL MLBB DATA:\n" +
                JSON.stringify(mlbbData) +
                "\n\nPLAYER DRAFT:\n" +
                JSON.stringify(draft)
            }
          ],
          max_completion_tokens: 1400,
          temperature: 0.2
        }),
        signal: AbortSignal.timeout(45000)
      }
    );

    const aiData = await aiResponse.json();

    if (!aiResponse.ok) {
      console.error("Groq error:", aiData.error?.message);

      return res.status(502).json({
        error: "Groq could not analyze this draft.",
        details: aiData.error?.message || "Unknown Groq error."
      });
    }

    const recommendation =
      aiData.choices?.[0]?.message?.content?.trim();

    if (!recommendation) {
      return res.status(502).json({
        error: "Groq returned an empty recommendation."
      });
    }

    return res.status(200).json({
      mode: "groq",
      aiAvailable: true,
      mlbbDataConnected: true,
      heroesLoaded: heroes.length,
      availableHeroes: catalogue.length,
      rankingsLoaded: rankings.length,
      pickedHeroesAnalyzed: pickedDetails.length,
      rankUsedForCounters: rank,
      requestedLane: lane,
      dataMeasuredAt: rankingResult.data?.measuredAt || null,
      source: "MLBBDex",
      sourceURL: "https://mlbbdex.com/en",
      recommendation
    });

  } catch (error) {
    console.error("Draft service error:", error);

    return res.status(500).json({
      error: "Could not load MLBB data or complete draft analysis.",
      details: error.message
    });
  }
}
