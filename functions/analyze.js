const admin = require("firebase-admin");
const axios = require("axios");
const { onDocumentWritten } = require("firebase-functions/v2/firestore");
const { defineSecret } = require("firebase-functions/params");
const FormData = require("form-data");
// Use secret for OpenAI Whisper API Key
const OPENAI_APIKEY = defineSecret("OPENAI_APIKEY");

// Use secret for QWEN API Key
const QWEN_API_KEY = defineSecret("QWEN_API_KEY");

// Shared parsing helper
function parseQwenResponse(raw) {
    const start = raw.indexOf("{");
    const end = raw.lastIndexOf("}");
    if (start === -1 || end === -1 || end <= start) {
        console.error("❌ Qwen‑Antwort enthielt kein JSON:", raw);
        return null;
    }
    try {
        return JSON.parse(raw.slice(start, end + 1));
    } catch (e) {
        console.error("❌ JSON‑Parse‑Fehler:", e, raw);
        return null;
    }
}

// Dream analysis trigger
exports.analyzeTraum = onDocumentWritten(
    { region: "europe-west3", path: "users/{userId}/traeume/{traumId}", secrets: [QWEN_API_KEY, OPENAI_APIKEY] },
    async (event) => {
        const before = event.data.before?.toJSON() || null;
        const after = event.data.after?.toJSON();
        const newlyCreated = before === null && after.isAnalyzed === false;
        // Trigger on any update where isAnalyzed is reset to false 
        const reAnalyze = before && after.isAnalyzed === false;
        if (!newlyCreated && !reAnalyze) return;

        // Transkription via OpenAI Whisper, falls noch nicht vorhanden
        let transcript = after.transcript;
        if ((!transcript || transcript.trim().length < 1) && after.audioUrl) {
            console.log("Starte Transkription via OpenAI Whisper...");
            // Datei herunterladen
            const audioResponse = await axios.get(after.audioUrl, { responseType: "arraybuffer" });
            const form = new FormData();
            form.append("file", Buffer.from(audioResponse.data), "audio.m4a");
            form.append("model", "whisper-1");
            const whisperResp = await axios.post(
                "https://api.openai.com/v1/audio/transcriptions",
                form,
                {
                    headers: {
                        ...form.getHeaders(),
                        Authorization: `Bearer ${OPENAI_APIKEY.value()}`,
                    },
                }
            );
            transcript = whisperResp.data.text;
            // Firestore aktualisieren
            await admin
                .firestore()
                .collection("users")
                .doc(event.context.params.userId)
                .collection("traeume")
                .doc(event.context.params.traumId)
                .update({ transcript });
        }

        if (transcript.trim().length < 5) {
            console.log("Transcript zu kurz oder leer");
            return;
        }
        console.log(`Starte Traum-Analyse für ${event.context.params.traumId}`);

        const prompt = `Analysiere den folgenden Traum und gib ausschließlich ein JSON-Objekt zurück mit diesen Feldern:
{
  "title": "Titel des Traumes (maximal 4 Wörter, verwende NICHT das Wort 'Traum')",
  "mainPoints": ["Erster Hauptpunkt", "Zweiter Hauptpunkt", "Dritter Hauptpunkt"], 
  "summary": "Zusammenfassung des Traumes (max. 5 Sätze oder 'Nicht verfügbar')",
  "storiesExamplesCitations": "Biblische Geschichten oder Zitate oder 'Keine passenden Beispiele'",
  "followUpQuestions": "Fragen zur persönlichen Reflexion oder 'Nicht verfügbar'",
  "actionItems": "Konkrete Handlungsschritte oder 'Nicht verfügbar'",
  "supportingScriptures": "Passende Bibelstellen oder 'Nicht verfügbar'",
  "relatedTopics": "Ähnliche geistliche Themen oder 'Nicht verfügbar'",
  "transcript": "${transcript}"
}
Hier ist das Transkript:
${transcript}`;

        try {
            const resp = await axios.post(
                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
                {
                    model: "qwen-turbo",
                    messages: [
                        { role: "system", content: "Du bist ein erfahrener christlicher Traumdeuter." },
                        { role: "user", content: prompt },
                    ],
                    temperature: 0.7,
                },
                {
                    headers: {
                        "Content-Type": "application/json",
                        Authorization: `Bearer ${QWEN_API_KEY}`,
                    },
                }
            );

            const raw = resp.data.choices[0].message.content;
            const parsed = parseQwenResponse(raw);
            if (!parsed) return;

            await admin
                .firestore()
                .collection("users")
                .doc(event.context.params.userId)
                .collection("traeume")
                .doc(event.context.params.traumId)
                .update({
                    title: parsed.title || "",
                    mainPoints: (parsed.mainPoints || []).join("\n"),
                    summary: parsed.summary || "",
                    verses: parsed.supportingScriptures || "",
                    actionItems: parsed.actionItems || "",
                    questions: parsed.followUpQuestions || "",
                    storiesExamplesCitations: parsed.storiesExamplesCitations || "",
                    relatedTopics: parsed.relatedTopics || "",
                    isAnalyzed: true,
                });

            console.log("Traum-Analyse abgeschlossen");
        } catch (e) {
            console.error("Fehler bei Qwen-Analyse:", e);
        }
    }
);

// Prophetie analysis trigger
exports.analyzeProphetie = onDocumentWritten(
    { region: "europe-west3", path: "users/{userId}/prophetien/{prophetieId}", secrets: [QWEN_API_KEY, OPENAI_APIKEY] },
    async (event) => {
        const before = event.data.before?.toJSON() || null;
        const after = event.data.after?.toJSON();
        const newlyCreated = before === null && after.isAnalyzed === false;
        // Trigger on any update where isAnalyzed is reset to false 
        const reAnalyze = before && after.isAnalyzed === false;
        if (!newlyCreated && !reAnalyze) return;

        // Transkription via OpenAI Whisper, falls noch nicht vorhanden
        let transcript = after.transcript;
        if ((!transcript || transcript.trim().length < 1) && after.audioUrl) {
            console.log("Starte Transkription via OpenAI Whisper...");
            // Datei herunterladen
            const audioResponse = await axios.get(after.audioUrl, { responseType: "arraybuffer" });
            const form = new FormData();
            form.append("file", Buffer.from(audioResponse.data), "audio.m4a");
            form.append("model", "whisper-1");
            const whisperResp = await axios.post(
                "https://api.openai.com/v1/audio/transcriptions",
                form,
                {
                    headers: {
                        ...form.getHeaders(),
                        Authorization: `Bearer ${OPENAI_APIKEY.value()}`,
                    },
                }
            );
            transcript = whisperResp.data.text;
            // Firestore aktualisieren
            await admin
                .firestore()
                .collection("users")
                .doc(event.context.params.userId)
                .collection("prophetien")
                .doc(event.context.params.prophetieId)
                .update({ transcript });
        }

        if (transcript.trim().length < 5) {
            console.log("Transcript zu leer");
            return;
        }
        console.log(`Starte Prophetie-Analyse für ${event.context.params.prophetieId}`);

        const prompt = `Analysiere die folgende Prophetie und gib ausschließlich ein JSON-Objekt zurück mit diesen Feldern:
{
  "title": "Titel der Prophetie (maximal 4 Wörter, verwende NICHT das Wort 'Prophetie')",
  "mainPoints": ["Erster Hauptpunkt", "Zweiter Hauptpunkt", "Dritter Hauptpunkt"], 
  "summary": "Zusammenfassung der Prophetie (max. 5 Sätze oder 'Nicht verfügbar')",
  "storiesExamplesCitations": "Biblische Geschichten oder Zitate oder 'Keine passenden Beispiele'",
  "followUpQuestions": "Fragen zur persönlichen Reflexion oder 'Nicht verfügbar'",
  "actionItems": "Konkrete Handlungsschritte oder 'Nicht verfügbar'",
  "supportingScriptures": "Passende Bibelstellen oder 'Nicht verfügbar'",
  "relatedTopics": "Ähnliche geistliche Themen oder 'Nicht verfügbar'",
  "transcript": "${transcript}"
}
Hier ist der Text der Prophetie:
${transcript}`;

        try {
            const resp = await axios.post(
                "https://dashscope-intl.aliyuncs.com/compatible-mode/v1/chat/completions",
                {
                    model: "qwen-turbo",
                    messages: [
                        { role: "system", content: "Du bist ein erfahrener christlicher Theologie-Professor." },
                        { role: "user", content: prompt },
                    ],
                    temperature: 0.7,
                },
                {
                    headers: {
                        "Content-Type": "application/json",
                        Authorization: `Bearer ${QWEN_API_KEY}`,
                    },
                }
            );

            const raw = resp.data.choices[0].message.content;
            const parsed = parseQwenResponse(raw);
            if (!parsed) return;

            await admin
                .firestore()
                .collection("users")
                .doc(event.context.params.userId)
                .collection("prophetien")
                .doc(event.context.params.prophetieId)
                .update({
                    title: parsed.title || "",
                    mainPoints: (parsed.mainPoints || []).join("\n"),
                    summary: parsed.summary || "",
                    verses: parsed.supportingScriptures || "",
                    actionItems: parsed.actionItems || "",
                    questions: parsed.followUpQuestions || "",
                    storiesExamplesCitations: parsed.storiesExamplesCitations || "",
                    relatedTopics: parsed.relatedTopics || "",
                    isAnalyzed: true,
                });

            console.log("Prophetie-Analyse abgeschlossen");
        } catch (e) {
            console.error("Fehler bei Qwen-Analyse:", e);
        }
    }
);