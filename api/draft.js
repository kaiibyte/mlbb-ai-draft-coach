
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
      message: "Groq API key is not configured."
    });
  }

  const draft = req.body?.draft;

  if (
    !draft ||
    typeof draft !== "object" ||
    Array.isArray(draft)
  ) {
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

  const rankAliases = {
    epic: "epic",
    legend: "legend",
    mythic: "mythic",
    honor: "honor",
    "mythical honor": "honor",
    glory: "glory",
    "mythical glory": "glory"
  };

  const requestedRank = String(
    draft.rank || "glory"
  ).toLowerCase();

  const rank =
    rankAliases[requestedRank] || "glory";

  const requestedLane = String(
    draft.lane || draft.requestedLane || "Gold"
  );

  const normalize = value =>
    String(value || "")
      .toLowerCase()
      .replace(/[^a-z0-9]/g, "");

  async function getJSON(url) {
    const response = await fetch(url, {
      headers: {
        Accept: "application/json"
      },
      signal: AbortSignal.timeout(8000)
    });

    if (!response.ok) {
      throw new Error(
        `MLBBDex request failed: ${response.status}`
      );
    }

    return response.json();
  }

  function getHeroName(item) {
    if (typeof item === "string") return item;
    return item?.name || item?.hero || "";
  }

  function getHeroField(hero, first, second) {
    return hero?.[first] ??
      hero?.[second] ??
      [];
  }

  try {
    // 1. Fetch actual MLBB data.

    const [heroResult, rankingResult] =
      await Promise.all([
        getJSON(`${BASE}/heroes`),
        getJSON(`${BASE}/rankings`)
      ]);

    const heroes = Array.isArray(heroResult.data)
      ? heroResult.data
      : [];

    const rankings = Array.isArray(
      rankingResult.data?.heroes
    )
      ? rankingResult.data.heroes
      : [];

    if (!heroes.length) {
      throw new Error(
        "MLBB hero catalogue is empty."
      );
    }

    if (!rankings.length) {
      throw new Error(
        "MLBB rankings are unavailable."
      );
    }

    // 2. Create hero lookup tables.

    const heroMap = new Map(
      heroes.map(hero => [
        normalize(hero.name),
        hero
      ])
    );

    const rankingMap = new Map(
      rankings.map(hero => [
        hero.slug,
        hero
      ])
    );

    // 3. Read allied and enemy picks.

    const allied = Array.isArray(draft.allied)
      ? draft.allied.map(getHeroName).filter(Boolean)
      : [];

    const enemy = Array.isArray(draft.enemy)
      ? draft.enemy.map(getHeroName).filter(Boolean)
      : [];

    const pickedNames = [
      ...new Set([...allied, ...enemy])
    ];

    // 4. Fetch counters for picked heroes.

    const counterResults = await Promise.allSettled(
      pickedNames.slice(0, 10).map(async name => {
        const hero = heroMap.get(normalize(name));

        if (!hero?.slug) return null;

        const result = await getJSON(
          `${BASE}/heroes/${encodeURIComponent(
            hero.slug
          )}/counters`
        );

        const counterData = result.data?.[rank];

        if (!counterData) return null;

        const resolveCounterNames = list =>
          (Array.isArray(list) ? list : []).map(item => ({
            hero:
              heroes.find(
                h => h.slug === item.slug
              )?.name || item.slug,
            advantage: item.advantage
          }));

        return {
          hero: hero.name,
          rank,
          baselineWinRate: counterData.winRate,
          strongAgainst: resolveCounterNames(
            counterData.strong
          ),
          weakAgainst: resolveCounterNames(
            counterData.weak
          )
        };
      })
    );

    const counters = counterResults
      .filter(result => result.status === "fulfilled")
      .map(result => result.value)
      .filter(Boolean);

    // 5. Prepare the complete hero catalogue.
    // Wanwan is deliberately excluded.

    const availableHeroes = heroes
      .filter(hero =>
        normalize(hero.name) !== "wanwan"
      )
      .map(hero => {
        const ranking = rankingMap.get(hero.slug);

        return {
          name: hero.name,
          slug: hero.slug,

          roles: getHeroField(
            hero,
            "roles",
            "role"
          ),

          lanes: getHeroField(
            hero,
            "lanes",
            "lane"
          ),

          specialties: getHeroField(
            hero,
            "specialties",
            "specialty"
          ),

          tier: ranking?.tier ?? null,
          winRate: ranking?.winRate ?? null,
          banRate: ranking?.banRate ?? null,
          pickRate: ranking?.pickRate ?? null,
          lowSample: ranking?.lowSample ?? null
        };
      });

    // 6. Prepare picked hero information.

    const pickedHeroDetails = pickedNames.map(name => {
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
        roles: getHeroField(hero, "roles", "role"),
        lanes: getHeroField(hero, "lanes", "lane"),
        specialties: getHeroField(
          hero,
          "specialties",
          "specialty"
        ),
        ranking: rankingMap.get(hero.slug) || null
      };
    });

    // 7. Prepare actual data for Groq.

    const mlbbData = {
      source: "MLBBDex",
      sourceURL: "https://mlbbdex.com/en",
      attribution: heroResult.source || null,
      rankingSource: rankingResult.source || null,
      rankingMeasuredAt:
        rankingResult.data?.measuredAt || null,

      rankUsedForCounters: rank,
      requestedLane,

      totalHeroes: heroes.length,
      availableHeroes: availableHeroes.length,

      allied,
      enemy,

      pickedHeroDetails,
      matchupCounters: counters,

      heroCatalogue: availableHeroes
    };

    // 8. Prepare draft coaching instructions.

    const instructions = `
You are an expert competitive Mobile Legends:
Bang Bang draft coach.

You are coaching a player who prefers Gold Lane,
especially flexible picks such as Fighter Gold.

PLAYER PREFERENCES:

- Consider ALL heroes.
- NEVER recommend Wanwan.
- Prioritize the requested lane: ${requestedLane}.
- Gold Lane is the default priority.
- Consider Fighter Gold, Mage Gold and Marksman Gold.
- Consider Tank EXP and Fighter EXP.
- Support legitimate flexible role and lane swaps.
- Do not assume a hero is viable in every lane.
- Do not recommend an off-meta lane swap without
  explaining its risks and conditions.

DRAFT ANALYSIS:

Evaluate:
- Allied and enemy compositions.
- Lane matchups.
- Hero counters.
- Hero synergies.
- Team fight potential.
- Frontline and durability.
- Physical and magic damage balance.
- Crowd control.
- Early, mid and late game strengths.
- Objective control.
- Best remaining picks.
- Ban recommendations.

STATISTICS:

- Use supplied MLBBDex rankings.
- Use the supplied ${rank} counter statistics.
- Distinguish overall ranking statistics from
  rank-specific matchup counters.
- Never invent statistics.
- Do not treat win rate alone as proof of a counter.
- Mention low sample warnings when relevant.
- Never claim the statistics are MPL statistics.

IMPORTANT:

- Recommend only heroes in the supplied catalogue.
- Exclude Wanwan completely.
- Never invent hero roles, lanes or statistics.
- If information is missing, say so.
- Explain WHY your recommendation fits the matchup.
- Do not simply recommend the highest win-rate hero.

RESPONSE FORMAT:

1. BEST PICK
2. TWO ALTERNATIVE PICKS
3. LANE MATCHUP
4. COUNTERS AND SYNERGIES
5. TEAM COMPOSITION ANALYSIS
6. DRAFT WARNINGS

Be concise, decisive and practical.
Speak like a professional MLBB coach helping
during a live ranked draft.
`;

    // 9. Send the actual data to Groq.

    const aiResponse = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",

        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${groqKey}`
        },

        body: JSON.stringify({
          model:
            process.env.GROQ_MODEL ||
            "openai/gpt-oss-120b",

          messages: [
            {
              role: "user",
              content:
                instructions +
                "\n\nACTUAL MLBB DATA:\n" +
                JSON.stringify(mlbbData) +
                "\n\nPLAYER DRAFT:\n" +
                JSON.stringify(draft)
            }
          ],

          max_completion_tokens: 1600,
          temperature: 0.4,
          include_reasoning: false,
          reasoning_effort: "low"
        }),

        signal: AbortSignal.timeout(45000)
      }
    );

    const aiData = await aiResponse.json();

    if (!aiResponse.ok) {
      console.error(
        "Groq error:",
        aiData.error?.message
      );

      return res.status(502).json({
        error: "Groq could not analyze this draft."
      });
    }

    const choice = aiData.choices?.[0];

    const recommendation =
      typeof choice?.message?.content === "string"
        ? choice.message.content.trim()
        : "";

    if (!recommendation) {
      console.error("Empty Groq response:", {
        finishReason: choice?.finish_reason,
        message: choice?.message
      });

      return res.status(502).json({
        error: "Groq returned no recommendation.",
        finishReason: choice?.finish_reason || null
      });
    }

    // 10. Return the result.

    return res.status(200).json({
      mode: "groq",
      aiAvailable: true,

      mlbbDataConnected: true,

      heroesLoaded: heroes.length,
      availableHeroes: availableHeroes.length,
      rankingsLoaded: rankings.length,
      countersLoaded: counters.length,

      rankUsedForCounters: rank,
      requestedLane,

      dataMeasuredAt:
        rankingResult.data?.measuredAt || null,

      source: "MLBBDex",
      sourceURL: "https://mlbbdex.com/en",

      recommendation
    });

  } catch (error) {
    console.error("Draft service error:", error);

    return res.status(500).json({
      error:
        "Could not load MLBB data or complete draft analysis."
    });
  }
}
