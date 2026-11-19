
export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  const apiKey = process.env.OPENAI_API_KEY;

  // Keep free/local mode available when no key is configured.
  if (!apiKey) {
    return res.status(200).json({
      mode: "local",
      aiAvailable: false,
      message: "OpenAI is not activated. Use local draft analysis."
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
      "https://api.openai.com/v1/responses",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}`
        },
        body: JSON.stringify({
          model: process.env.OPENAI_MODEL || "gpt-5.4-mini",
          instructions: `
You are an expert Mobile Legends: Bang Bang draft coach.

Analyze the supplied draft carefully.

Consider:
- Allied and enemy heroes
- Team composition and roles
- Hero counters and synergies
- Damage balance
- Crowd control
- Frontline and durability
- Draft weaknesses
- Best remaining hero picks

Only use information supplied in the draft.
Never invent win rates, statistics, patch data, or hero ownership.
If information is missing, say so.

Give practical, concise recommendations.
Explain WHY a recommendation is good.
Do not recommend heroes marked as not owned.
`,
          input: draftText,
          max_output_tokens: 600
        })
      }
    );

    const data = await response.json();

    if (!response.ok) {
      console.error("OpenAI API error:", data.error?.message);

      return res.status(502).json({
        error: "The AI service could not process this draft."
      });
    }

    // Read the generated text from the Responses API output.
    let recommendation = data.output_text || "";

    if (!recommendation && Array.isArray(data.output)) {
      recommendation = data.output
        .filter(item => item.type === "message")
        .flatMap(item => item.content || [])
        .filter(item => item.type === "output_text")
        .map(item => item.text || "")
        .join("\n");
    }

    if (!recommendation) {
      return res.status(502).json({
        error: "The AI returned an empty recommendation."
      });
    }

    return res.status(200).json({
      mode: "openai",
      aiAvailable: true,
      recommendation
    });

  } catch (error) {
    console.error("Draft AI error:", error);

    return res.status(500).json({
      error: "AI service temporarily unavailable."
    });
  }
}
