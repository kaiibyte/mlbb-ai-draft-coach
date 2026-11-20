
export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const apiKey = process.env.GROQ_API_KEY;

  if (!apiKey) {
    return res.status(500).json({
      error: "GROQ_API_KEY is missing."
    });
  }

  const draft = req.body?.draft;

  if (!draft || typeof draft !== "object" || Array.isArray(draft)) {
    return res.status(400).json({
      error: "A valid draft object is required."
    });
  }

  const BASE = "https://mlbbdex.com/api/v1";
  const normalize = value =>
    String(value || "").toLowerCase().replace(/[^a-z0-9]/g, "");

  try {
    const response = await fetch(`${BASE}/heroes`, {
      headers: { Accept: "application/json" },
      signal: AbortSignal.timeout(12000)
    });

    if (!response.ok) {
      throw new Error(`MLBBDex error: ${response.status}`);
    }

    const result = await response.json();
    const heroes = Array.isArray(result.data) ? result.data : [];

    if (!heroes.length) {
      throw new Error("MLBBDex returned no heroes.");
    }

    const catalogue = heroes
      .filter(hero => normalize(hero.name) !== "wanwan")
      .map(hero => ({
        name: hero.name,
        roles: hero.roles ?? hero.role ?? [],
        lanes: hero.lanes ?? hero.lane ?? []
      }));

    const allied = Array.isArray(draft.allied)
      ? draft.allied.map(h =>
          typeof h === "string" ? h : h?.name
        ).filter(Boolean).slice(0, 5)
      : [];

    const enemy = Array.isArray(draft.enemy)
      ? draft.enemy.map(h =>
          typeof h === "string" ? h : h?.name
        ).filter(Boolean).slice(0, 5)
      : [];

    const lane = String(
      draft.lane || draft.requestedLane || "Gold"
    );

    const rank = String(draft.rank || "glory");

    const instructions = `
You are an expert Mobile Legends draft coach.

Use ONLY the supplied hero catalogue and draft information.

RULES:
- Never recommend Wanwan.
- Only recommend heroes in the supplied catalogue.
- Never invent skills, abilities, counters, statistics or win rates.
- Do not claim ranked data is MPL or professional data.
- Consider all available heroes, not just Marksmen.
- Prioritize the requested lane: ${lane}.
- Consider flexible picks, including Fighter Gold, Mage Gold,
  Tank EXP and Fighter EXP when suitable.
- Consider team composition and matchup as strategic judgment,
  not verified statistics.
- Keep the response short and useful.

Return exactly this structure:

BEST PICK: Hero name

ALTERNATIVES:
1. Hero
2. Hero
3. Hero
4. Hero
5. Hero

REASON:
One short explanation.

LANE:
One short explanation.

WARNINGS:
Only important concerns. Say "None" if there are none.
`;

    const userData = {
      lane,
      rank,
      allied,
      enemy,
      availableHeroes: catalogue
    };

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
              content: JSON.stringify(userData)
            }
          ],
          max_completion_tokens: 700,
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
      requestedLane: lane,
      rankRequested: rank,
      source: "MLBBDex",
      sourceURL: "https://mlbbdex.com/en",
      recommendation
    });

  } catch (error) {
    console.error("Draft service error:", error);

    return res.status(500).json({
      error: "Could not complete draft analysis.",
      details: error.message
    });
  }
}
