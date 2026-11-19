
export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");

    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  const apiKey = process.env.GROQ_API_KEY;

  // Free local mode if Groq is not configured.
  if (!apiKey) {
    return res.status(200).json({
      mode: "local",
      aiAvailable: false,
      message: "Groq is not activated. Use local draft analysis."
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

  const draftText = JSON.stringify(draft);

  if (draftText.length > 20000) {
    return res.status(413).json({
      error: "Draft information is too large."
    });
  }

  try {
    const response = await fetch(
      "https://api.groq.com/openai/v1/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`
        },
        body: JSON.stringify({
          model: process.env.GROQ_MODEL || "openai/gpt-oss-120b",

          messages: [
            {
              role: "system",
              content: `
You are an expert Mobile Legends: Bang Bang draft coach.

Your job is to analyze drafts and give accurate,
competitive recommendations.

Analyze:

- Allied and enemy heroes
- Hero counters and synergies
- Team composition
- Damage balance
- Crowd control
- Frontline and durability
- Team fight potential
- Draft weaknesses
- Best remaining hero picks
- Ban recommendations

IMPORTANT RULES:

1. Only use supplied MLBB data.
2. Never invent win rates or statistics.
3. Never pretend outdated information is current.
4. Respect the player's owned-hero list.
5. Never recommend heroes marked as not owned.
6. Explain WHY each recommendation is good.
7. Give concise, practical advice suitable for a live draft.
8. If information is missing, clearly say so.

Respond like a professional MLBB draft coach.
`
            },
            {
              role: "user",
              content: "Analyze this Mobile Legends draft:\n" + draftText
            }
          ],

          max_completion_tokens: 800,
          temperature: 0.5
        })
      }
    );

    const data = await response.json();

    if (!response.ok) {
      console.error("Groq API error:", data.error?.message);

      return res.status(502).json({
        error: "The AI service could not process this draft."
      });
    }

    const recommendation =
      data.choices?.[0]?.message?.content || "";

    if (!recommendation.trim()) {
      return res.status(502).json({
        error: "Groq returned an empty recommendation."
      });
    }

    return res.status(200).json({
      mode: "groq",
      aiAvailable: true,
      model: data.model,
      recommendation
    });

  } catch (error) {
    console.error("Groq draft error:", error);

    return res.status(500).json({
      error: "AI service temporarily unavailable."
    });
  }
}
