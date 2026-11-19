
export default async function handler(req, res) {
  if (req.method !== "POST") {
    return res.status(405).json({
      error: "Method not allowed"
    });
  }

  // No API key means no paid requests.
  const apiKey = process.env.OPENAI_API_KEY;

  if (!apiKey) {
    return res.status(200).json({
      mode: "local",
      aiAvailable: false,
      message: "OpenAI is not activated. Use local draft analysis."
    });
  }

  const { draft } = req.body || {};

  if (!draft || typeof draft !== "object") {
    return res.status(400).json({
      error: "A valid draft object is required."
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
          model: process.env.OPENAI_MODEL || "gpt-6-luna",
          instructions:
            "You are an expert Mobile Legends Bang Bang draft coach. Analyze the supplied allied and enemy picks, roles, counters, synergies and draft weaknesses. Never invent current win rates or patch data. Use only supplied data. Give concise practical recommendations.",
          input: JSON.stringify(draft),
          max_output_tokens: 500
        })
      }
    );

    const data = await response.json();

    if (!response.ok) {
      return res.status(response.status).json({
        error: "OpenAI request failed",
        details: data.error?.message || "Unknown API error"
      });
    }

    return res.status(200).json({
      mode: "openai",
      aiAvailable: true,
      recommendation: data.output_text || "No recommendation returned."
    });

  } catch (error) {
    return res.status(500).json({
      error: "AI service unavailable."
    });
  }
}
