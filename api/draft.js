
export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  const groqKey = process.env.GROQ_API_KEY;

  if (!groqKey) {
    return res.status(200).json({
      mode: "local",
      aiAvailable: false,
      message: "Groq is not configured."
    });
  }

  const draft = req.body?.draft;

  if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
    return res.status(400).json({
      error: "A valid draft object is required."
    });
  }

  if (JSON.stringify(draft).length > 20000) {
    return res.status(413).json({
      error: "Draft information is too large."
    });
  }

  const BASE = "https://mlbbdex.com/api/v1";

  async function getJSON(url) {
    const response = await fetch(url, {
      headers: {
        "Accept": "application/json"
      },
      signal: AbortSignal.timeout(4500)
    });

    if (!response.ok) {
      throw new Error(`MLBBDex returned ${response.status}`);
    }

    return response.json();
  }

  function normalize(value) {
    return String(value || "")
      .toLowerCase()
      .replace(/[^a-z0-9]/g, "");
  }

  try {
    // 1. Fetch the hero catalogue and rankings.
    const [heroResult, rankingResult] = await Promise.all([
      getJSON(`${BASE}/heroes`),
      getJSON(`${BASE}/rankings`)
    ]);

    const heroes = heroResult.data || [];
    const rankings = rankingResult.data?.heroes || [];

    if (!heroes.length || !rankings.length) {
      throw new Error("MLBB data is incomplete.");
    }

    const heroMap = new Map(
      heroes.map(hero => [normalize(hero.name), hero])
    );

    const rankingMap = new Map(
      rankings.map(hero => [hero.slug, hero])
    );

    // 2. Collect picked heroes.
    const allied = Array.isArray(draft.allied)
      ? draft.allied
      : [];

    const enemy = Array.isArray(draft.enemy)
      ? draft.enemy
      : [];

    const pickedNames = [...new Set(
      [...allied, ...enemy].filter(
        item => typeof item === "string"
      )
    )];

    // 3. Fetch counter data for picked heroes.
    const counterResults = await Promise.allSettled(
      pickedNames.slice(0, 10).map(async name => {
        const hero = heroMap.get(normalize(name));

        if (!hero) return null;

        const result = await getJSON(
          `${BASE}/heroes/${encodeURIComponent(hero.slug)}/counters`
        );

        return {
          hero: hero.name,
          counters: result.data
        };
      })
    );

    const rank = [
      "epic",
      "legend",
      "mythic",
      "honor",
      "glory"
    ].includes(draft.rank)
      ? draft.rank
      : "glory";

    // 4. Prepare picked hero information.
    const pickedData = pickedNames.map(name => {
      const hero = heroMap.get(normalize(name));

      if (!hero) {
        return {
          name,
          found: false
        };
      }

      return {
        name: hero.name,
        slug: hero.slug,
        roles: hero.roles,
        lanes: hero.lanes,
        specialties: hero.specialties,
        rankings: rankingMap.get(hero.slug) || null
      };
    });

    // 5. Prepare counter information.
    const counters = counterResults
      .filter(result => result.status === "fulfilled")
      .map(result => result.value)
      .filter(Boolean)
      .map(item => ({
        hero: item.hero,
        rank,
        data: item.counters?.[rank] ||
              item.counters?.all ||
              null
      }));

    // 6. Prepare owned-hero candidates.
    const ownedHeroes = Array.isArray(draft.ownedHeroes)
      ? draft.ownedHeroes
      : Array.isArray(draft.ownedHeroNames)
        ? draft.ownedHeroNames
        : [];

    const ownedSet = new Set(ownedHeroes.map(normalize));

    const candidates = ownedHeroes.length
      ? rankings.filter(hero => ownedSet.has(normalize(hero.name)))
      : rankings.slice(0, 30);

    const candidateData = candidates.map(hero => {
      const catalogue = heroMap.get(normalize(hero.name));

      return {
        name: hero.name,
        roles: catalogue?.roles || [],
        lanes: catalogue?.lanes || [],
        specialties: catalogue?.specialties || [],
        tier: hero.tier,
        winRate: hero.winRate,
        banRate: hero.banRate,
        pickRate: hero.pickRate,
        lowSample: hero.lowSample
      };
    });

    // 7. Build the information for Groq.
    const mlbbData = {
      source: "MLBBDex / Mobile Legends Wiki",
      sourceURL: "https://mlbbdex.com/en",
      license: "CC BY-SA",
      measuredAt: rankingResult.data?.measuredAt || null,
      rankUsedForCounters: rank,
      allied,
      enemy,
      pickedHeroes: pickedData,
      matchupCounters: counters,
      ownedHeroListProvided: ownedHeroes.length > 0,
      availableCandidates: candidateData
    };

    const prompt = `
Analyze this Mobile Legends: Bang Bang draft.

REAL GAME DATA:
${JSON.stringify(mlbbData)}

PLAYER INFORMATION:
${JSON.stringify(draft)}

INSTRUCTIONS:

1. Use the supplied MLBBDex information.
2. Analyze allied and enemy team compositions.
3. Use counter data for matchup recommendations.
4. Consider hero roles, lanes and specialties.
5. Consider win rate, pick rate, ban rate and tier.
6. Do not invent statistics or counters.
7. Do not recommend heroes outside availableCandidates.
8. If an owned hero list was provided, recommend ONLY owned heroes.
9. If no owned list was provided, explain that ownership is unknown.
10. Recommend the best available pick and explain why.
11. Consider team balance, damage, crowd control and frontline.
12. Be concise and useful during a live draft.
13. If data is missing, say so.

The counter statistics use the selected rank.
Overall ranking statistics may cover a broader population.

Give:
- Best pick
- Two alternative picks
- Important matchup warnings
- Draft strengths and weaknesses
- Short explanation for your choices
`;

    // 8. Ask Groq to analyze the collected data.
    const aiResponse = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${groqKey}`
        },
        body: JSON.stringify({
          model: process.env.GROQ_MODEL ||
            "openai/gpt-oss-120b",
          messages: [
            {
              role: "system",
              content:
                "You are an expert competitive Mobile Legends draft coach."
            },
            {
              role: "user",
              content: prompt
            }
          ],
          max_completion_tokens: 1000,
          temperature: 0.4
        })
      }
    );

    const aiData = await aiResponse.json();

    if (!aiResponse.ok) {
      console.error("Groq error:", aiData.error?.message);

      return res.status(502).json({
        error: "Groq could not analyze this draft."
      });
    }

    const recommendation =
      aiData.choices?.[0]?.message?.content || "";

    if (!recommendation.trim()) {
      return res.status(502).json({
        error: "Groq returned an empty recommendation."
      });
    }

    return res.status(200).json({
      mode: "groq",
      aiAvailable: true,
      mlbbDataConnected: true,
      heroesLoaded: heroes.length,
      rankingsLoaded: rankings.length,
      countersLoaded: counters.length,
      rankUsedForCounters: rank,
      dataMeasuredAt: rankingResult.data?.measuredAt || null,
      source: mlbbData.source,
      sourceURL: mlbbData.sourceURL,
      recommendation
    });

  } catch (error) {
    console.error("Draft service error:", error);

    return res.status(500).json({
      error: "Could not load MLBB data or complete draft analysis."
    });
  }
}
