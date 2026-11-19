
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

  if (JSON.stringify(draft).length > 10000) {
    return res.status(413).json({ error: "Draft is too large." });
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

  const rankInput = String(draft.rank || "glory").toLowerCase();
  const rank = rankAliases[rankInput] || "glory";
  const lane = String(draft.lane || draft.requestedLane || "Gold");

  const normalize = value =>
    String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");

  async function getJSON(url) {
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(8000)
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

  try {
    // Load MLBB heroes and rankings.
    const [heroResult, rankingResult] = await Promise.all([
      getJSON(`${BASE}/heroes`),
      getJSON(`${BASE}/rankings`)
    ]);

    const heroes = Array.isArray(heroResult.data) ? heroResult.data : [];
    const rankings = Array.isArray(rankingResult.data?.heroes)
      ? rankingResult.data.heroes
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

    const pickedNames = [...new Set([...allied, ...enemy])];

    // Fetch matchup data for selected heroes.
    const counterResults = await Promise.allSettled(
      pickedNames.slice(0, 10).map(async name => {
        const hero = heroMap.get(normalize(name));
        if (!hero?.slug) return null;

        const result = await getJSON(
          `${BASE}/heroes/${encodeURIComponent(hero.slug)}/counters`
        );

        const data = result.data?.[rank];
        if (!data) return null;

        const resolve = list =>
          (Array.isArray(list) ? list : []).slice(0, 5).map(item => ({
            hero: heroes.find(h => h.slug === item.slug)?.name || item.slug,
            advantage: item.advantage
          }));

        return {
          hero: hero.name,
          winRate: data.winRate ?? null,
          strongAgainst: resolve(data.strong),
          weakAgainst: resolve(data.weak)
        };
      })
    );

    const counters = counterResults
      .filter(result => result.status === "fulfilled")
      .map(result => result.value)
      .filter(Boolean);

    // Keep every hero available, but use compact fields.
    const catalogue = heroes
      .filter(hero => normalize(hero.name) !== "wanwan")
      .map(hero => {
        const stats = rankingMap.get(hero.slug);

        return {
          name: hero.name,
          roles: getField(hero, "roles", "role"),
          lanes: getField(hero, "lanes", "lane"),
          tier: stats?.tier ?? null,
          winRate: stats?.winRate ?? null
        };
      });

    // Compact ranking list: only top 25.
    const topRanked = [...rankings]
      .sort((a, b) => (Number(b.winRate) || 0) - (Number(a.winRate) || 0))
      .slice(0, 25)
      .map(hero => ({
        hero: heroes.find(h => h.slug === hero.slug)?.name || hero.slug,
        tier: hero.tier ?? null,
        winRate: hero.winRate ?? null,
        pickRate: hero.pickRate ?? null,
        banRate: hero.banRate ?? null
      }));

    const pickedDetails = pickedNames.map(name => {
      const hero = heroMap.get(normalize(name));
      if (!hero) return { name, found: false };

      return {
        name: hero.name,
        roles: getField(hero, "roles", "role"),
        lanes: getField(hero, "lanes", "lane"),
        stats: rankingMap.get(hero.slug) || null
      };
    });

    const mlbbData = {
      source: "MLBBDex",
      measuredAt: rankingResult.data?.measuredAt || null,
      rank,
      requestedLane: lane,
      allied,
      enemy,
      pickedDetails,
      counters,
      catalogue,
      topRanked
    };

    const instructions = `
You are a professional Mobile Legends Bang Bang draft coach.

PLAYER:
- Consider every hero except Wanwan.
- Preferred lane: ${lane}.
- Especially consider Fighter Gold.
- Also consider legitimate Mage Gold, Marksman Gold, Tank EXP and Fighter EXP picks.
- Do not recommend unrealistic lane swaps without explaining risks.

ANALYZE:
- Allied and enemy compositions.
- Lane matchups.
- Counters and synergies.
- Damage balance, frontline and crowd control.
- Early, mid and late game.
- Objective control.
- Best remaining pick and ban advice.

RULES:
- Recommend only heroes in the supplied catalogue.
- Never recommend Wanwan.
- Never invent statistics or matchup facts.
- Use supplied statistics carefully.
- Distinguish ranked data from professional/MPL data.
- No MPL statistics are supplied here.
- Explain why your recommendation is good.

FORMAT:
1. BEST PICK
2. TWO ALTERNATIVES
3. LANE MATCHUP
4. COUNTERS AND SYNERGIES
5. TEAM COMPOSITION
6. WARNINGS

Be concise and decisive.
`;

    // Send compact MLBB data to Groq.
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
                "MLBB DATA:\n" +
                JSON.stringify(mlbbData) +
                "\n\nPLAYER DRAFT:\n" +
                JSON.stringify(draft)
            }
          ],
          max_completion_tokens: 1400,
          temperature: 0.4
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
      countersLoaded: counters.length,
      rankUsedForCounters: rank,
      requestedLane: lane,
      dataMeasuredAt: rankingResult.data?.measuredAt || null,
      source: "MLBBDex",
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
